# SwilClip v1 — Prompt Manager 设计文档

> ## ✅ 已解封 / 将实施 (REOPENED — 2026-08-20)
>
> **本文档于 2026-05-28 被否决，于 2026-08-20 解封。** 见
> [ADR-0002](../adr/0002-reopen-prompt-library.md)。
>
> 解封理由：原否决的三条理由全部是**市场理由**（"这是另一个产品"、"和 Raycast
> 冲突"、"用户会不会离开"）。项目目标已转为「自用工具 + 作品集」，市场理由不再成立。
> 本文档头部当年写下的解封条件——"理解过去为何拒绝，再讨论是否情况变化"——已满足。
>
> **实施版本与本稿的差异**（以
> [v2 spec](../superpowers/specs/2026-08-20-swift-rewrite-prompt-library-design.md)
> 为准，本文件保留为设计沿革）：
>
> | 本稿设计 | v2 实际 | 原因 |
> |---|---|---|
> | TypeScript + Rust IPC | **Swift 原生** | ADR-0001 |
> | `{{变量}}` 占位符 + 填写弹窗 | **不做** | 真实语料无一用到，YAGNI |
> | `tags[]` 分类 | **不做** | 5–10 条量级，搜索足够；标签是录入时的额外决策点 |
> | title 必填 | **首行自动生成，可改** | 录入摩擦决定自用工具的生死 |
> | 无跨面板动作 | **`⇧S` 从剪贴板提升为 Prompt** | 合体的唯一不可拆分收益 |
>
> 保留 Tab 切换架构、独立存储、粘贴不污染历史流这三项核心设计。

---

**状态：** ✅ 已解封（2026-08-20）— 作为设计沿革保留，实施以 v2 spec 为准
**关联版本：** v2 / M2
**范围：** Prompt 库核心功能

---

## 一、产品定位

SwilClip v0 是一个「被动」工具——你复制什么，它记什么。

v1 的 Prompt Manager 引入「主动管理」维度：用户可以将常用的 AI Prompt 显式保存为「片段库」，脱离 50 条自动淘汰机制，长期保留并随时召唤。

```
v0:  系统剪贴板 → [监听] → 历史流 → 粘贴
v1:  系统剪贴板 → [监听] → 历史流 ─┐
                                    ├─ Tab 切换 ─→ [粘贴 / 发送]
     手动输入 / 从历史保存 → Prompt库 ─┘
```

核心用户场景：
- 日常 AI 工作流中频繁复用的指令（代码 Review Prompt、翻译指令、总结模板）
- 含变量占位符的半结构化模板（`{{语言}}`、`{{内容}}`）
- 不希望被剪贴板历史淘汰的「重要片段」

---

## 二、数据模型

### 2.1 PromptItem（新增类型）

```typescript
// src/types/prompt.ts
interface PromptItem {
  id: string;                  // UUID v4
  title: string;               // 用户起的名字，用于列表展示
  body: string;                // Prompt 正文（含 {{变量}} 占位符）
  tags: string[];              // 分类标签（如 ["代码", "review"]）
  isPinned: boolean;           // 置顶，复用 v0 Pin 语义
  createdAt: number;           // ms timestamp
  updatedAt: number;           // ms timestamp
}
```

**变量占位符规则：**
- 语法：`{{变量名}}`，变量名仅限字母、数字、中文、下划线
- 同名占位符视为同一变量（一次填写，全局替换）
- 无占位符的 Prompt 直接粘贴，不弹填写框

### 2.2 Rust 侧镜像结构

```rust
// src-tauri/src/prompt/types.rs
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PromptItem {
    pub id: String,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
    pub is_pinned: bool,
    pub created_at: i64,
    pub updated_at: i64,
}
```

---

## 三、存储设计

独立存储文件，与剪贴板历史隔离：

| 文件 | 用途 | 容量限制 |
|------|------|----------|
| `clipboard_history.json` | v0 历史流（不变） | 50 条，FIFO 淘汰 |
| `prompts.json` | Prompt 库 | **无上限**（用户主动管理） |

两者都通过 `tauri-plugin-store` 读写，复用现有基础设施，无需引入新依赖。

存储 key 规范：
```
prompts.json → key: "prompts" → Vec<PromptItem>
```

---

## 四、Rust 后端

### 4.1 新增模块结构

```
src-tauri/src/
├── prompt/
│   ├── mod.rs        # 模块导出
│   ├── types.rs      # PromptItem 结构体
│   └── store.rs      # CRUD 操作（≤150行）
└── commands.rs       # 新增 4 个 IPC command（现有文件扩展）
```

### 4.2 新增 IPC Commands

```rust
// 追加到 commands.rs（保持现有 7 个命令不变）

#[tauri::command]
pub fn get_prompts(app_handle: AppHandle) -> Result<Vec<PromptItem>, String>

#[tauri::command]
pub fn add_prompt(app_handle: AppHandle, prompt: PromptItem) -> Result<(), String>

#[tauri::command]
pub fn update_prompt(app_handle: AppHandle, prompt: PromptItem) -> Result<(), String>

#[tauri::command]
pub fn delete_prompt(app_handle: AppHandle, id: String) -> Result<(), String>
```

**粘贴流程复用：** Prompt 粘贴不新增 Rust 命令。变量替换在前端完成，替换后调用现有 `paste_item` 所依赖的底层路径——即将填写后的正文写入 NSPasteboard 并模拟 Cmd+V。具体实现：前端生成一个临时 ClipItem（`clipType: "text"`, `content: 替换后的body`）直接调用 `invoke("paste_item")` 之前先通过新 command `paste_text` 传递纯文本，避免对历史库造成污染。

> 替代方案：新增 `paste_raw_text(text: String)` command，直接写入 pasteboard + 模拟 Cmd+V，完全绕过历史流。推荐此方案，更干净。

```rust
#[tauri::command]
pub fn paste_raw_text(app_handle: AppHandle, text: String) -> Result<(), String>
// 复用 simulate::write_and_paste 的底层逻辑，不经过 store
```

---

## 五、前端架构

### 5.1 新增文件

```
src/
├── types/
│   └── prompt.ts              # PromptItem interface（≤30行）
├── hooks/
│   └── usePromptLibrary.ts    # CRUD hook，镜像 useClipboardHistory 模式
├── components/
│   ├── PromptPanel.tsx        # Prompt 列表面板（≤250行）
│   └── PromptEditor.tsx       # 新建/编辑弹窗（≤200行）
│   └── VariableFillDialog.tsx # 变量填写弹窗（≤150行）
```

### 5.2 usePromptLibrary Hook

```typescript
// src/hooks/usePromptLibrary.ts
// 镜像 useClipboardHistory 的结构，无事件监听（Prompt 库只在用户操作时变更）

interface UsePromptLibraryReturn {
  prompts: PromptItem[];
  status: 'loading' | 'success' | 'error';
  addPrompt: (prompt: Omit<PromptItem, 'id' | 'createdAt' | 'updatedAt'>) => Promise<void>;
  updatePrompt: (prompt: PromptItem) => Promise<void>;
  deletePrompt: (id: string) => Promise<void>;
  refresh: () => Promise<void>;
}
```

### 5.3 Tab 切换架构

`ClipboardPanel` 扩展为 Tab 容器，新增顶部 Tab Bar：

```
┌─────────────────────────────────┐  ← 拖拽区（保持不变）
│  [Clipboard]  [Prompts]         │  ← Tab Bar（新增）
├─────────────────────────────────┤
│  ... 对应面板内容 ...            │
├─────────────────────────────────┤
│  ↑↓ ⏎ d p e s  esc             │  ← Hint bar（随 Tab 更新）
└─────────────────────────────────┘
```

- `Tab` 键：在两个面板之间切换
- 切换后焦点回到对应面板的列表根节点
- 两个面板各自维护独立的 `selectedValue` 和 `mode`（navigate/search）

### 5.4 PromptPanel 键盘交互

复用 ClipboardPanel 的键盘模式，差异如下：

| 按键 | Clipboard 面板 | Prompt 面板 |
|------|---------------|-------------|
| `⏎` | 粘贴到前台应用 | 检测变量 → 填写对话框 → 粘贴 |
| `d` | 删除条目 | 删除条目 |
| `p` | 置顶/取消置顶 | 置顶/取消置顶 |
| `n` | 不适用 | 新建 Prompt（打开 PromptEditor） |
| `e` | 展开全文 | 打开 PromptEditor 编辑 |
| `s` | 进入搜索模式 | 进入搜索模式（按 title + body 搜索） |

### 5.5 变量填写流程

```
用户按 ⏎ 选中含 {{变量}} 的 Prompt
  ↓
前端解析 body，提取所有唯一变量名
  ↓
若有变量 → 弹出 VariableFillDialog（每个变量一个 input）
  ↓
用户填写 → 确认
  ↓
前端做字符串替换（全局替换同名变量）
  ↓
调用 paste_raw_text(替换后的文本) → 写入 NSPasteboard + 模拟 Cmd+V
  ↓
弹窗关闭，主面板隐藏
```

变量解析正则：`/\{\{([a-zA-Z0-9_\u4e00-\u9fa5]+)\}\}/g`

---

## 六、PromptEditor 设计

弹窗字段：

| 字段 | 组件 | 说明 |
|------|------|------|
| 标题 | `<input>` | 必填，最长 80 字符 |
| 正文 | `<textarea>` | 必填，支持多行，显示字符数 |
| 标签 | Tag input（逗号分隔） | 可选，用于分类搜索 |
| 变量预览 | 只读 badge 列表 | 自动解析正文中的 `{{变量}}` 并展示 |

编辑器实时展示检测到的变量（作为 badge），帮助用户确认模板结构正确。

---

## 七、不在 v1 范围内（Defer to v2）

| 功能 | 原因 |
|------|------|
| 调用 Claude / ChatGPT API | 需要 API Key 管理、隐私设计，复杂度独立 |
| 本地 LLM 语义搜索 | 依赖 Ollama/ONNX，属独立里程碑 |
| 团队共享 Prompt 库 | iCloud/网络同步冲突解决超出 v1 范围 |
| Prompt 版本历史 | 可在 v1 稳定后作为增量功能 |
| 按来源应用过滤 | 依赖 v0 补全 `appName` 字段 |
| Prompt 导入/导出 | 文件格式标准化可延后 |

---

## 八、实现顺序建议

1. `src-tauri/src/prompt/` 模块 + 4 个 IPC commands + `paste_raw_text`
2. `src/types/prompt.ts` + `usePromptLibrary.ts` hook
3. `PromptPanel.tsx`（列表 + 键盘导航，先不含编辑）
4. `ClipboardPanel.tsx` Tab 切换扩展
5. `PromptEditor.tsx` 新建/编辑弹窗
6. `VariableFillDialog.tsx` 变量填写流程
7. 集成测试：粘贴含/不含变量的 Prompt，验证历史库不被污染

---

## 九、设计约束（遵循 .cursor/ 开发守则）

- 每个新文件职责单一，不超过 300 行
- 无 `any` 类型；状态用 Discriminated Union（`'loading' | 'success' | 'error'`）
- `usePromptLibrary` 中的异步 Effect 须有 ignore 标志防止 race condition
- 常量（最大标题长度、变量正则）提取到 `src/constants/index.ts`，不内联魔法值
- Rust 侧：`prompt/store.rs` 和 `prompt/types.rs` 分离，`commands.rs` 仅做参数转发
