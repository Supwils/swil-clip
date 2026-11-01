# SwilClip - 极简剪贴板管理工具

## 1. 产品愿景 (Product Vision)

打造一款为极致效率和键盘操作而生的 macOS 原生级剪贴板管理工具。产品形态对标 Maccy（竖向窄屏、轻量隐蔽），拒绝过度设计，追求毫秒级的启动响应、绝对稳定的布局（零 Layout Thrashing），以及如艺术品般优雅直观的纯键盘交互体验。

**产品路线（已锁定，2026-05-28）：极简纯粹派 / "更现代的 Maccy"。** 详见 [version-roadmap.md](./version-roadmap.md#产品方向已锁定--非目标-non-goals) 顶部的「产品方向 / Non-Goals」章节——这是判断任何新需求是否要做的首要依据。

## 2. 技术栈架构 (Tech Stack)

| 层级 | 技术选型 | 版本 |
|------|---------|------|
| 桌面框架 | Tauri 2.0 (Rust) | 2.10+ |
| 前端框架 | React + Vite + TypeScript (strict) | React 19, Vite 6 |
| 样式 | Tailwind CSS 4 + CSS Variables (`global.css`) | 4.2+ |
| 组件库 | shadcn/ui — 核心依赖 `Command` (cmdk) | latest |
| 持久化 | `tauri-plugin-store` (JSON, 50 条上限) | 2.x |
| 全局快捷键 | `tauri-plugin-global-shortcut` | 2.x |
| 系统托盘 | Tauri tray-icon (内置) | 2.x |
| 包管理器 | pnpm | 10.x |

### 关键 Rust 依赖

| Crate | 用途 |
|-------|------|
| `cocoa` + `objc` | 调用 macOS `NSPasteboard` 读写剪贴板 |
| `core-graphics` | `CGEvent` 模拟 `Cmd+V` 按键 |
| `window-vibrancy` | macOS 原生毛玻璃效果 |
| `base64` | 图片数据编码 |
| `uuid` + `chrono` | 生成唯一 ID 和时间戳 |

## 3. 核心功能需求 (Core Features - MVP)

### 3.1 剪贴板监听与存储 (Silent Monitoring)

* **后台静默运行:** App 启动后常驻系统托盘 (System Tray)，不在 Dock 栏显示图标。
* **多模态支持 (文本 + 图片):**
    * 支持纯文本、代码片段。
    * 支持图片复制：Rust 端读取 `NSPasteboard` 中的 TIFF/PNG 数据，转换为 Base64，前端按缩略图展示。
* **去重与淘汰机制:** 连续复制相同内容时不重复记录。全局严格限制最多保留 **50 条**历史记录，超出时自动淘汰最旧数据（FIFO）。
* **轮询频率:** Rust 后台线程每 **500ms** 检测一次 `NSPasteboard` 变化计数。

### 3.2 极速呼出与交互 (Summon & Interact)

* **全局快捷键:** `Cmd + Shift + V` 呼出/隐藏主界面。窗口出现在鼠标光标当前位置附近。
* **纯键盘导航 (基于 cmdk):**
    * 呼出后即进入导航模式（`s` 切换到搜索框输入查询）。
    * `↑` / `↓` 键切换选中项；`Home` / `End`、`Cmd+↑/↓` 跳首/末；列表循环。
    * `Enter` 键 — **默认（Auto Paste = false）**：把选中项写回系统剪贴板 + 隐藏面板 + 把焦点还给呼出前台 App（Terminal、编辑器等的输入框保持光标），**不**模拟 `Cmd+V`，由用户自行决定何时何处按 ⌘V。设置里把 **Auto Paste** 打开后改为 Enter 直接模拟 `Cmd+V` 粘到原 App。
    * 前 9 条记录支持 `⌥+1` ~ `⌥+9` (Option/Alt) 秒选，行为与 `Enter` 一致（受 Auto Paste 开关影响）。
    * `d` 删除当前项、`p` 切换 Pin、`e` 展开/收起长文本预览、`u` 撤销最近一次删除。
    * `Esc` 键或窗口失焦 (Blur) 时瞬间隐藏窗口；显式隐藏路径（Esc / Enter / 再次按全局快捷键关闭）都会调用 `restore_previous_focus` 把焦点还给前台 App。

### 3.3 剪贴板回写与可选 Paste-Back 闭环

回写剪贴板与焦点恢复是**始终启用的默认行为**；模拟 `Cmd+V` 是**可选**的 Auto Paste 模式，单独开关。

**默认（Manual / Copy-only）模式 — 不需要 Accessibility 权限**
* Rust 端将选中数据回写 `NSPasteboard`（`simulate::write_only`）。
* 显式激活呼出面板时记下的前台 App（`focus_target::activate_stored_now`），让其输入框光标继续闪烁。
* 不发送任何模拟按键事件。

**Auto Paste 模式（设置开启）**
* 同样回写 `NSPasteboard`（`simulate::write_and_paste`）。
* 先 `activate_stored_before_paste`（含 ~100ms 焦点切换缓冲），再用 `CoreGraphics` `CGEvent` API 模拟 `Cmd+V` 按键事件。
* 写入和模拟之间保持 **50ms** 延迟确保系统剪贴板更新。
* 需要在 **System Settings → Privacy & Security → Accessibility** 中授权 SwilClip。

### 3.4 系统托盘

* 托盘图标菜单包含 **Show SwilClip** 和 **Quit** 两项。
* 单击托盘图标也可显示主窗口。

## 4. UI/UX 设计规范 (Design System)

* **窗口尺寸:** 340px (宽) x 480px (高), 无边框 (Frameless), 不可调整大小。
* **视觉风格:** 极简深色模式。macOS 原生毛玻璃 (`UnderWindowBackground` vibrancy)，12px 圆角。
* **字体:**
    * UI 标签: `DM Sans` (Google Fonts)
    * 剪贴板内容: `SF Mono` / `Fira Code` (等宽，适合代码)
* **色彩:**
    * 前景文字: `hsl(220, 15%, 92%)` 冷白
    * 选中高亮: `hsl(215, 60%, 45% / 0.2)` 极微蓝光
    * 背景: 半透明深色 `hsl(220, 15%, 12% / 0.65)`
    * 强调色: `hsl(215, 70%, 55%)`
* **排版:** 文本项严格单行截断 (`...`)，图片项显示 32x32 缩略图 + 尺寸/格式元信息。

## 5. 项目结构 (Project Structure)

```
swil-clip/
├── src/                              # React 前端
│   ├── main.tsx                      # 入口
│   ├── App.tsx                       # 根组件（薄层，仅接线）
│   ├── global.css                    # CSS Variables + Tailwind 主题
│   ├── lib/utils.ts                  # cn() 工具
│   ├── types/clipboard.ts            # ClipItem, ClipType 类型定义
│   ├── constants/index.ts            # MAX_HISTORY, 窗口尺寸等常量
│   ├── components/
│   │   ├── ui/                       # shadcn/ui 原子组件
│   │   ├── ClipboardPanel.tsx        # 主面板 (包裹 Command)
│   │   └── ClipItem.tsx              # 单条记录行
│   └── hooks/
│       ├── useClipboardHistory.ts    # Tauri IPC: 监听 + 获取历史
│       └── useClipboardActions.ts    # 粘贴、删除、清空操作
├── src-tauri/                        # Rust 后端
│   ├── src/
│   │   ├── lib.rs                    # App 构建器，插件注册，窗口定位
│   │   ├── main.rs                   # 入口
│   │   ├── clipboard/
│   │   │   ├── mod.rs                # 模块导出
│   │   │   ├── monitor.rs            # NSPasteboard 轮询监听
│   │   │   └── types.rs              # ClipItem 结构体 + 序列化
│   │   ├── commands.rs               # #[tauri::command] IPC 命令
│   │   ├── store.rs                  # tauri-plugin-store 持久化
│   │   ├── simulate.rs               # CGEvent Cmd+V 模拟
│   │   └── tray.rs                   # 系统托盘设置
│   ├── Cargo.toml
│   ├── tauri.conf.json               # 窗口配置: 无边框, 透明, 毛玻璃
│   └── capabilities/default.json     # Tauri 权限声明
├── docs/
│   └── init-doc.md                   # 产品需求文档（本文件）
├── package.json
├── vite.config.ts
├── tsconfig.json
└── components.json                   # shadcn/ui 配置
```

## 6. IPC 命令清单 (Tauri Commands)

| 命令 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `get_history` | 无 | `Vec<ClipItem>` | 加载全部历史记录 |
| `delete_item` | `id: String` | `()` | 删除单条记录 |
| `clear_history` | 无 | `()` | 清空全部历史 |
| `clear_unpinned` | 无 | `Vec<ClipItem>` | 清空未 Pin 的项（返回被清空的项供 Undo） |
| `restore_items` | `items: Vec<ClipItem>` | `()` | Undo：把刚清空/删除的项写回 |
| `pin_item` | `id, pinned` | `()` | 切换单项的 Pin 状态 |
| `reorder_items` | `orderedIds, pinnedIds` | `()` | 拖拽重排后提交新顺序 |
| `paste_item` | `id: String` | `()` | 写回剪贴板 + `activate_stored`；Auto Paste 关闭时仅复制不粘贴，开启时再模拟 `Cmd+V` |
| `restore_previous_focus` | 无 | `()` | 仅恢复呼出前的前台 App 焦点（Esc/失焦关闭时调用） |
| `get_settings` / `update_global_shortcut` / `update_max_history` / `update_auto_paste` | — | — | 读写应用设置 |

## 7. 事件清单 (Tauri Events)

| 事件名 | Payload | 方向 | 说明 |
|--------|---------|------|------|
| `clipboard-changed` | `ClipItem` | Rust -> Frontend | 新内容被复制时触发 |

## 8. 开发阶段划分 (Milestones)

1. **Phase 1 - 基础脚手架:** Tauri + React + Vite + Tailwind CSS 4 + TypeScript strict。
2. **Phase 2 - UI 组件:** shadcn/ui `Command` 组件，毛玻璃窗口，深色主题。
3. **Phase 3 - Rust 剪贴板后端:** NSPasteboard 轮询，tauri-plugin-store 持久化，系统托盘，全局快捷键。
4. **Phase 4 - 前后端集成:** React Hooks + Tauri IPC，键盘导航，搜索过滤，窗口自动隐藏。
5. **Phase 5 - Paste-Back 闭环:** CGEvent 模拟 Cmd+V，光标位置定位窗口，动画润色。

## 9. 版本规划（v0 / v1）

当前已实现能力汇总为 **v0**，下一阶段目标与优化方向见 **[version-roadmap.md](./version-roadmap.md)**（以仓库代码为 v0 事实来源，文档随发布更新）。
