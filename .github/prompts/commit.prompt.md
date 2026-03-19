---
description: "根据当前 git 变更生成中文 Conventional Commits 格式的 commit message"
agent: agent
---

查看当前仓库的 git 变更（staged 和 unstaged），生成一条中文 git commit message，放在代码块中方便复制。

## 格式要求

严格遵循 [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)：

```
<type>(<scope>): <中文描述>

[可选正文]
```

- **type** 和 **scope** 用英文：`feat`, `fix`, `chore`, `docs`, `test`, `perf`, `refactor`, `style`, `ci`, `build`
- **scope** 使用包名或模块名：`hmi`, `arm`, `driver`, `policy`, `joy_to_servo`, `moveit_config`, `lerobot`, `dev` 等
- **描述**用中文，简洁精炼，不超过 50 字
- 如果修改跨多个包，可省略 scope 或使用最主要的包名
- 不加句号结尾

## 参考风格

```
feat(hmi): 录制屏幕支持 BACK 键丢弃当前 episode
fix(hmi): 修正 RECORD 模式切换时机
chore(dev): fix dev setup script and update teabot_hmi install deps
docs(plan): 更新 SmolVLA 训练与推理整合方案
test(hmi): 为 HmiNode 添加单元测试
perf(hmi): 优化 Episode List 构建性能
refactor(arm): 重构运动规划异步调用逻辑
```

## 步骤

1. 运行 `git diff --cached --stat` 和 `git diff --cached` 查看 staged 变更；若无 staged 变更则查看 `git diff HEAD --stat` 和 `git diff HEAD`
2. 分析变更内容，判断合适的 type 和 scope
3. 用中文概括变更意图（不是罗列文件）
4. 如果变更较大，可在正文中分点说明
5. 输出 commit message 放在 ```text 代码块中
