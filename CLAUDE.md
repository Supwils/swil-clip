# CLAUDE.md — swil-clip

Guidance for AI coding agents in this repo. Instructions here override default behavior.

swil-clip is a Tauri + Vite + React + TypeScript desktop app (macOS-first; `swilclip` on GitHub).

## 语言规则
- **对用户始终用中文回复**；代码、标识符、注释一律英文。

## 动 selection / 删除 / 键盘导航之前必读
先读 [docs/code-review.md](docs/code-review.md) 的 "Standing hazard" 一节。`<Command>` 是受控模式，但 **cmdk 自己另存了一份 selection**，且会在选中项卸载时自行改写它、不经过 React。`ClipboardPanel` 里的 `flushSync` 迁移、`onValueChange` 接线、以及"用 `item.id` 而非内容做 key"这三点都是**承重的**，拆掉任何一个都会让 0.1.2 那个"按 `d` 删错行"的 bug 复活。`deleteSelection.test.tsx` 里跨 `setTimeout` 的 IPC mock 同样承重——**不要把那个延迟"优化"掉**，微任务级的 mock 会让整类时序 bug 隐形。

## Git 纪律
- **不要自动 commit / push**。只有用户明确说"commit / push / 提交 / 推送"时才执行。改完代码停在工作树，等用户决定何时落库。

## Push 前置校验（`.githooks/pre-push`）
每次 `git push` 前自动跑 `pnpm prepush`（= `typecheck`(tsc --noEmit) + `lint` + `test`），确保 broken tree / 类型错误进不了远端。经 `git config core.hooksPath .githooks` 激活（`prepare` 脚本在 `pnpm install` 时自动设）。**刻意不含** Tauri/Rust `build` 与 `release:mac`（重、平台相关），留给手动打包。紧急绕过：`git push --no-verify`。
> ⚠️ 首次装上后请在机器空闲时本地 `pnpm prepush` 自验一次确认绿（含 `tsc`，内存紧张会 OOM exit 137，届时用 `--no-verify`）。
