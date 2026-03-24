#!/bin/bash
# ==============================================================================
# render.sh — cloud-init 模板合并 + 占位符替换
# ==============================================================================
#
# Usage:
#   render.sh --base <base.yaml> --overlay <overlay.yaml> [--var KEY=VALUE ...] [-o output]
#   render.sh --help
#
# Description:
#   将 base cloud-init 模板与 overlay 合并，生成最终的 user-data 文件。
#   overlay 中的特殊 key 控制合并行为：
#
#     packages:         追加到 base 的 packages 列表
#     write_files:      追加到 base 的 write_files 列表
#     runcmd:           追加到 base 的 runcmd 列表末尾
#     runcmd_prepend:   插入到 base 的 runcmd 列表开头
#     users_merge:      合并到 base 的 users[0]（如 ssh_authorized_keys）
#     power_state:      覆盖/追加为顶层 key
#
#   占位符替换通过 --var KEY=VALUE 传入，支持 __KEY__ 格式。
#
# Options:
#   --base FILE         base cloud-init 模板（必需）
#   --overlay FILE      overlay 文件（必需，可多次指定）
#   --var KEY=VALUE     占位符替换（可多次指定，替换 __KEY__）
#   -o, --output FILE   输出文件（默认：stdout）
#   -h, --help          显示帮助
#
# Examples:
#   # RPi：base + rpi overlay
#   render.sh \
#     --base deploy/cloud-init/base-user-data.yaml \
#     --overlay deploy/cloud-init/rpi-overlay.yaml \
#     --var HOSTNAME=hermes \
#     --var TIMEZONE=Asia/Shanghai \
#     --var TAILSCALE_AUTHKEY=tskey-auth-xxx \
#     --var SSH_PUBKEY="ssh-ed25519 AAAA..." \
#     -o /tmp/user-data
#
#   # Dev VM：base + dev overlay
#   render.sh \
#     --base deploy/cloud-init/base-user-data.yaml \
#     --overlay deploy/cloud-init/dev-overlay.yaml \
#     --var HOSTNAME=muliao-dev \
#     --var TIMEZONE=Asia/Shanghai \
#     -o /tmp/user-data
# ==============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #
die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*" >&2; }

show_help() {
    sed -n '/^# Usage:/,/^# ====/{/^# ====/d; p}' "$0" | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
base_file=""
overlay_files=()
declare -A vars=()
output_file=""

if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
    -h|--help)
        show_help; exit 0 ;;
    --base)
        [[ $# -ge 2 ]] || die "--base 需要参数"
        base_file="$2"; shift 2 ;;
    --overlay)
        [[ $# -ge 2 ]] || die "--overlay 需要参数"
        overlay_files+=("$2"); shift 2 ;;
    --var)
        [[ $# -ge 2 ]] || die "--var 需要 KEY=VALUE 格式"
        local_key="${2%%=*}"
        local_val="${2#*=}"
        vars["$local_key"]="$local_val"
        shift 2 ;;
    -o|--output)
        [[ $# -ge 2 ]] || die "-o 需要参数"
        output_file="$2"; shift 2 ;;
    *)
        die "未知参数: $1" ;;
    esac
done

[[ -n "$base_file" ]] || die "必须指定 --base"
[[ -f "$base_file" ]] || die "base 文件不存在: $base_file"
[[ ${#overlay_files[@]} -gt 0 ]] || die "至少指定一个 --overlay"
for f in "${overlay_files[@]}"; do
    [[ -f "$f" ]] || die "overlay 文件不存在: $f"
done

# --------------------------------------------------------------------------- #
# YAML section extraction helpers
# --------------------------------------------------------------------------- #
# 提取 YAML 顶层 key 的内容块（从 key: 到下一个顶层 key 或文件末尾）。
# 仅处理 cloud-init 常见的简单结构，不是通用 YAML 解析器。

# 提取列表类 section 的条目（去掉 key 行和注释行，保留缩进内容）
extract_list_items() {
    local file="$1" key="$2"
    awk -v key="$key:" '
        BEGIN { found=0 }
        /^[a-zA-Z_]/ {
            if ($0 ~ "^"key) { found=1; next }
            else if (found) { exit }
        }
        found && /^[[:space:]]/ { print }
    ' "$file"
}

# 提取整个 section（含 key 行）
extract_section() {
    local file="$1" key="$2"
    awk -v key="$key:" '
        BEGIN { found=0 }
        /^[a-zA-Z_]/ {
            if ($0 ~ "^"key) { found=1; print; next }
            else if (found) { exit }
        }
        found { print }
    ' "$file"
}

# 检查文件是否包含某个顶层 key
has_key() {
    local file="$1" key="$2"
    grep -qE "^${key}:" "$file" 2>/dev/null
}

# --------------------------------------------------------------------------- #
# Merge logic
# --------------------------------------------------------------------------- #
# 工作原理：
# 1. 以 base 为基础，逐行输出
# 2. 对每个列表类 section（packages, write_files, runcmd），
#    在 base 的该 section 末尾追加 overlay 的条目
# 3. 对 runcmd_prepend，插入到 base runcmd 的开头
# 4. 对 users_merge.ssh_authorized_keys，追加到 base users section
# 5. 对 power_state 等顶层 key，追加到文件末尾

merge() {
    local base="$1"
    shift
    local overlays=("$@")

    # 收集所有 overlay 的追加内容
    local pkgs_extra="" wf_extra="" runcmd_extra="" runcmd_prepend="" ssh_keys="" power_state=""

    for ov in "${overlays[@]}"; do
        if has_key "$ov" "packages"; then
            pkgs_extra+=$'\n'"$(extract_list_items "$ov" "packages")"
        fi
        if has_key "$ov" "write_files"; then
            wf_extra+=$'\n'"$(extract_list_items "$ov" "write_files")"
        fi
        if has_key "$ov" "runcmd"; then
            runcmd_extra+=$'\n'"$(extract_list_items "$ov" "runcmd")"
        fi
        if has_key "$ov" "runcmd_prepend"; then
            runcmd_prepend+=$'\n'"$(extract_list_items "$ov" "runcmd_prepend")"
        fi
        if has_key "$ov" "users_merge"; then
            # 提取 ssh_authorized_keys 列表项
            ssh_keys+=$'\n'"$(awk '
                /^users_merge:/      { in_um=1; next }
                /^[a-zA-Z_]/        { in_um=0 }
                in_um && /ssh_authorized_keys:/ { in_sak=1; next }
                in_um && in_sak && /^[[:space:]]*-/ { print "      " $0; next }
                in_um && in_sak && !/^[[:space:]]/ { in_sak=0 }
            ' "$ov")"
        fi
        if has_key "$ov" "power_state"; then
            power_state="$(extract_section "$ov" "power_state")"
        fi
    done

    # 逐行处理 base，在对应 section 末尾插入 overlay 内容
    local current_section="" next_is_new_section=0
    local in_users=0 users_done=0
    local pkg_appended=0 wf_appended=0 runcmd_appended=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 检测顶层 key
        if [[ "$line" =~ ^[a-zA-Z_] ]]; then
            # 在离开上一个 section 之前，追加 overlay 内容
            if [[ "$current_section" == "packages" && "$pkg_appended" -eq 0 ]]; then
                [[ -n "$pkgs_extra" ]] && echo "$pkgs_extra"
                pkg_appended=1
            elif [[ "$current_section" == "write_files" && "$wf_appended" -eq 0 ]]; then
                [[ -n "$wf_extra" ]] && echo "$wf_extra"
                wf_appended=1
            elif [[ "$current_section" == "runcmd" && "$runcmd_appended" -eq 0 ]]; then
                [[ -n "$runcmd_extra" ]] && echo "$runcmd_extra"
                runcmd_appended=1
            fi

            # 更新 current section
            if [[ "$line" =~ ^packages: ]]; then
                current_section="packages"
            elif [[ "$line" =~ ^write_files: ]]; then
                current_section="write_files"
            elif [[ "$line" =~ ^runcmd: ]]; then
                current_section="runcmd"
            elif [[ "$line" =~ ^users: ]]; then
                current_section="users"
                in_users=1
            else
                current_section=""
                in_users=0
            fi
        fi

        # 输出当前行
        echo "$line"

        # 在输出 runcmd: 行之后，紧接着插入 prepend 内容
        if [[ "$current_section" == "runcmd" && "$line" =~ ^runcmd: ]]; then
            [[ -n "$runcmd_prepend" ]] && echo "$runcmd_prepend"
        fi

        # 在 users section 的 ssh_authorized_keys 之后注入 overlay 的 keys
        # （简化处理：在 users section 的 sudo: 行之后注入）
        if [[ "$in_users" -eq 1 && "$users_done" -eq 0 && "$line" =~ "sudo:" ]]; then
            if [[ -n "$ssh_keys" ]]; then
                echo "    ssh_authorized_keys:"
                echo "$ssh_keys"
            fi
            users_done=1
        fi

    done < "$base"

    # 处理 base 最后一个 section 的追加
    if [[ "$current_section" == "packages" && "$pkg_appended" -eq 0 ]]; then
        [[ -n "$pkgs_extra" ]] && echo "$pkgs_extra"
    elif [[ "$current_section" == "write_files" && "$wf_appended" -eq 0 ]]; then
        [[ -n "$wf_extra" ]] && echo "$wf_extra"
    elif [[ "$current_section" == "runcmd" && "$runcmd_appended" -eq 0 ]]; then
        [[ -n "$runcmd_extra" ]] && echo "$runcmd_extra"
    fi

    # 追加 overlay 独有的顶层 key
    if [[ -n "$power_state" ]]; then
        echo ""
        echo "$power_state"
    fi
}

# --------------------------------------------------------------------------- #
# Placeholder substitution
# --------------------------------------------------------------------------- #
substitute_vars() {
    local content="$1"
    for key in "${!vars[@]}"; do
        content="${content//__${key}__/${vars[$key]}}"
    done
    echo "$content"
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
info "合并: $(basename "$base_file") + $(printf '%s ' "${overlay_files[@]/#/$(basename )")"

merged=$(merge "$base_file" "${overlay_files[@]}")

# 应用占位符替换
result=$(substitute_vars "$merged")

# 清理多余空行（连续 3+ 空行压缩为 2 行）
result=$(echo "$result" | awk '
    /^$/ { empty++; if (empty <= 2) print; next }
    { empty=0; print }
')

if [[ -n "$output_file" ]]; then
    mkdir -p "$(dirname "$output_file")"
    echo "$result" | tr -d '\r' > "$output_file"
    info "输出: $output_file"
else
    echo "$result" | tr -d '\r'
fi
