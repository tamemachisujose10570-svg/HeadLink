# 私有仓库与云端构建设置

私有仓库 https://github.com/wch33e/HeadLink 已连接。2026-10-16 已实测 connector 可读取仓库、写入 Contents 和 `.github/workflows/ios.yml`；工作流初始提交为 `19fa5cfb5cf9a943785001d9efca12881e0ff544`。CLI 现有 repo 授权可通过 REST 上传普通文件并运行 Actions，工作流文件使用 connector 写入，无需扩大 CLI scope。

## 最少人工步骤

1. 在 [GitHub 创建仓库](https://github.com/new)：名称可用 `HeadLink`，选择 **Private**。建立空仓库即可，不需要初始化 README。不要选公开来换免费额度。
2. 把生成的仓库 URL 发给开发助手。如果希望使用 connector，进入 GitHub 的 Installed GitHub Apps 管理，为 Codex 连接仅增加这个仓库，避免授权所有仓库。
3. 如果沿用本机已登录的 GitHub CLI，新增工作流提交权限可在你自己的终端运行 `gh auth refresh -h github.com -s workflow`，按浏览器提示授权。验证码和账户登录只在本地/官方页面完成，不要把 token、密码发到聊天。
4. 在 GitHub 账户的 Billing / Budgets and alerts 查看 Actions 免费分钟、当前使用量和产物存储。配置预算及 **Stop usage when budget limit is reached**（如你的账户界面提供），不设置付费预算，不启用超额继续运行。组织仓库由管理员核实策略。没有确认额度/禁止超额之前，不触发 macOS 构建。
5. 授权上传代码后，本地工程的 `project.yml`、源码和 `.github/workflows/ios.yml` 一起提交到你的仓库。只更新项目分支，不会涉及别的仓库。
6. 仓库 Actions → `iPhone unsigned build` → Run workflow。这个工作流只有 workflow_dispatch，不会因每次 push 自动耗费构建额度。

## 权限对应

| 操作 | GitHub App / fine-grained 权限 | CLI OAuth/PAT 说明 |
| --- | --- | --- |
| 读取私有源码 | Metadata read、Contents read | 现有 repo scope 可以覆盖 |
| 上传本项目源码 | Contents read/write | 私有仓库通常需要 repo |
| 创建/修改 workflow 文件 | Workflows write（授权界面若提供）及 Contents write | 当前 CLI 还需要 workflow scope |
| 运行和取消 Actions | Actions read/write | 需要可写仓库与可用 Actions API；connector 不一定暴露 dispatch |
| 读取日志与下载产物 | Actions read | 不需要 Apple 密钥 |

不需要仓库删除权限、组织管理、Apple 账户密码、签名证书或 Secrets。workflow 自身 `GITHUB_TOKEN` 只读 Contents，checkout 不保留凭据。若 connector 不支持运行 Actions，可以使用已授权 gh CLI 或你在浏览器手动点击。

## 费用提示

[GitHub 官方计费说明](https://docs.github.com/en/billing/concepts/product-billing/github-actions)：私有仓库构建分钟与存储取决于账户计划，超额可能收费，费用计入仓库所有者。macOS runner 成本与 Linux 不同；不能用 Linux 的免费分钟简单当作 macOS 实际可用分钟。

这个工作流单次上限 25 分钟、取消同分支过时运行、产物保留 3 天，不使用付费 larger runner，不自动重试整条工作流。上限和短保留不能代替账户账单控制。首次构建预计用量尚无实测，需先核实免费额度后再运行。

参考：[GitHub 创建仓库](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)、[手动运行工作流](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/manually-running-a-workflow)。
