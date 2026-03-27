

# 📋 SwilClip - 极简剪贴板管理工具 

## 1. 产品愿景 (Product Vision)
打造一款为极致效率和键盘操作而生的 macOS 原生级剪贴板管理工具。产品形态对标 Maccy（竖向窄屏、轻量隐蔽），拒绝过度设计，追求毫秒级的启动响应、绝对稳定的布局（零 Layout Thrashing），以及如艺术品般优雅直观的纯键盘交互体验。

## 2. 技术栈架构 (Tech Stack)
* **底层框架:** Tauri 2.0 (Rust)
    * *职责:* 极低内存占用常驻后台，注册全局快捷键，监听系统 `NSPasteboard`。
* **前端框架:** React + Vite + TypeScript + pnpm
    * *职责:* 高效渲染视图，处理用户交互。
* **样式与组件库 (核心):** Tailwind CSS + `shadcn/ui` (基于 Radix UI) 请下载shadcn skills  pnpm dlx skills add shadcn/ui
    * *职责:* 使用 Tailwind 进行极简的原子化样式控制（暗黑模式、无边框磨砂玻璃）。
    * *关键组件:* **重度依赖 `shadcn/ui` 的 `Command` (cmdk) 组件**，天生接管焦点管理、完美的 `↑` / `↓` 键盘导航、列表滚动跟随以及回车触发事件，确保代码整洁和丝滑体验。
* **本地存储:** `tauri-plugin-store` (JSON 格式)
    * *职责:* 因为历史上限仅为 50 条，直接采用轻量的 JSON 文件存储，摒弃 SQLite，最大化降低系统开销。

## 3. 核心功能需求 (Core Features - MVP)
### 3.1 剪贴板监听与存储 (Silent Monitoring)
* **后台静默运行:** App 启动后常驻系统托盘 (System Tray) 或完全隐藏，不在 Dock 栏显示图标。
* **多模态支持 (文本 + 图片):** * 支持纯文本、代码片段。
    * **支持图片复制:** Rust 端读取 `NSPasteboard` 中的图片数据，转换为 Base64 或存入本地临时目录，前端按缩略图展示。
* **去重与淘汰机制:** 连续复制相同内容时不重复记录。全局严格限制最多保留 **50 条**历史记录，超出时自动淘汰最旧数据（FIFO）。

### 3.2 极速呼出与交互 (Summon & Interact)
* **轻量隐蔽的呼出:** 默认 `Cmd + Shift + V`（或 `Option + V`）呼出主界面。窗口应出现在鼠标当前位置附近，采用**竖向窄屏**设计。
* **纯键盘导航 (基于 cmdk):**
    * 呼出后，输入框默认 Focus，直接打字进行全局模糊搜索。
    * 使用 `↑` / `↓` 键上下切换选中项（UI 不抖动）。
    * 按下 `Enter` 键直接将内容（文本或图片）写入系统剪贴板，并自动调用 macOS API 模拟 `Cmd + V` 粘贴到当前活动窗口，随后隐藏面板。
    * 前 9 条记录支持 `Cmd + 1~9` 快捷键秒贴。
    * 按下 `Esc` 键或失去焦点 (Blur) 时瞬间隐藏窗口。

## 4. UI/UX 设计规范 (Design System)
* **窗口尺寸:** 竖向窄屏结构（建议宽度约 300px~350px，最大高度约 500px），内容超出时内部滚动。
* **视觉风格:** 极简、扁平、无边框 (Frameless)。强制开启 macOS 原生毛玻璃背景 (Vibrancy / Window Blur)，适中圆角。
* **色彩搭配:** 深色模式优先，高对比度的冷白/浅灰文字，极其微弱的选中项高亮背景，彻底摒弃“卡片式 (Card)”布局，采用紧凑的 List 结构。
* **排版原则:** * 文本项：严格单行截断（尾部 `...`），绝对禁止随内容撑开高度。
    * 图片项：显示等比例裁剪的小尺寸缩略图（Thumbnail），附带图片尺寸或格式信息。

## 5. 开发阶段划分 (Milestones for Cursor)
1.  **Phase 1 - 基础脚手架:** 初始化 Tauri + React + Vite 项目，配置 Tailwind CSS。
2.  **Phase 2 - 引入无头组件:** 重点安装和配置 `shadcn/ui`，导入 `Command` 组件并修改默认样式以适配磨砂玻璃和窄屏 UI。
3.  **Phase 3 - 锈化底层 (Rust 剪贴板):** 在 Rust 端调用 `NSPasteboard`，实现文本和图片的读取，并通过 Tauri IPC 实时推送到前端；配置 `tauri-plugin-store` 实现 50 条数据的持久化。
4.  **Phase 4 - 灵魂交互:** 将前端 React 状态与 `cmdk` 绑定，跑通上下键导航、搜索过滤。
5.  **Phase 5 - 闭环体验:** 在 Rust 端实现数据回写剪贴板，并利用 `CoreGraphics` 或类似 API 模拟触发 `Cmd + V` 按键事件。

