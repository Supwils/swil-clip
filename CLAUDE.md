# CLAUDE.md — swil-clip

给在这个仓库里工作的 AI agent 看的。这里的规则**覆盖**默认行为。

swil-clip 是一个 macOS 剪贴板管理器 + 提示词库(`swilclip` on GitHub)。

---

## 0. 三条最容易违反的

1. **不要自动 commit / push。** 只有用户明确说"commit / push / 提交 / 推送"才执行。
   改完停在工作树。
2. **对用户始终用中文回复**;代码、标识符、注释一律英文。
3. **不要动 `tauri/`。** 它冻结在 v0.1.3,见 §2。

---

## 1. 仓库结构 —— 两棵树,只有一棵是活的

```
swift/    活跃版本。Swift 6 + AppKit + SwiftUI,零第三方依赖。所有新工作在这里。
tauri/    已冻结在 v0.1.3。Tauri 2 + React + Rust。只修不再演进。
docs/     ADR、设计规范、评审登记册。
```

**2026-08-20 起 `tauri/` 冻结**,见 [ADR-0001](docs/adr/0001-freeze-tauri-adopt-swift.md)。
除非用户明确要求,**不要给它加功能或修 bug** —— `docs/code-review.md` 里除 SC-05(已修)外的
open findings **一律不修**,其中 SC-07/SC-17/SC-18 已被 Swift 重写的存储模型从结构上消解。
它留在仓库里是刻意的:两次技术选型的证据。

`tauri/` 里的旧约定(`flushSync` 迁移、`onValueChange` 接线、用 `item.id` 做 key)
在冻结树里仍然承重,但**不适用于 `swift/`**。

---

## 2. 项目目标 —— 决定一切优先级

目标只有两条,没有第三条(见 [ADR-0002](docs/adr/0002-reopen-prompt-library.md)):

- **(a)** 作者每天自用的工具;
- **(b)** 一份证明端到端交付能力的作品。

**没有用户,没有市场。** 因此:

- 判断新需求用**两问**:①我自己会不会真的用?②这段代码值不值得被人读?两个都否就不做。
- 排序时 **correctness / 静默数据丢失 / 安全叙事自洽性 一律高于新功能**。
- 出现"为 star 数/下载量调整功能优先级"的苗头要**提醒用户**,那是偏离 (a)(b)。

`docs/version-roadmap.md` 的 Non-Goals 仍然有效,**但提示词库已于 2026-08-20 解禁**。
`{{变量}}`、tags、文件夹、同步、跨平台、AI 功能**仍然不做**。

---

## 3. 分层 —— 什么该放哪

**`SwilClipCore` 不许 import AppKit。** 它是纯 Swift,全部测试无 GUI 可跑(220 个,约 0.15s)。
任何"不需要窗口就能决定"的逻辑都属于这里:键盘映射、选择状态机、面板定位几何、搜索、
存储、加密、文案目录、快捷键说明书。app target 只做 `NSEvent` 拆包和窗口。

**零第三方依赖是刻意的**(spec §4.2)。加依赖前先问是否真的划算。

判据:**"这条规则能不能写成一个没有窗口的测试?"** 能,就属于 Core。

---

## 4. selection 与键盘 —— 这里出过最严重的线上 bug

v1 最严重的线上 bug 是**按 `d` 删错行**:cmdk 自己另存了一份 selection 并在选中项卸载时
绕过 React 改写它。两个真相源,其中一个不可见。

**v2 的答案是架构性的,不是修补:**

- selection 只存在于 `SelectionReducer.State` 一处;
- 每个按键 → `KeyCommand` → `SelectionReducer.reduce(...)`,**纯函数**;
- 删除后的下一个选中项**在删除前**就由 reducer 用旧列表算好;
- **视图只读 selection,永远不写。**
- reducer 只接收**当前渲染的列表**(`visibleIDs`),不是全量列表 —— 传全量就是让那个 bug 复活。

`SelectionReducerTests` 里每一条都对应那个 bug 走过的一个状态。**不要删,不要"简化"。**

### 4.1 方向键导航(selection 的第二根轴)

`←/→` 走行内按钮、`↑` 从第一行上到顶栏、`⏎` 触发停住的那个按钮。同样的规矩:

- **焦点只存在 `State.focus` 一处**(`PanelFocus`),视图只读不写。它决定 `⏎` 干什么。
- **焦点跟 `RowAction` 的身份走,绝不跟下标走。** 文本行 4 个按钮、图片行 3 个;用下标会让
  焦点从「存词库」悄悄滑到「展开」—— 删错行换了个马甲。
- **按钮由 `ClipItem/PromptItem.rowActions` 生成,reducer 收到同一个数组。** 不许在 view 里
  手写按钮 HStack。
- **`⏎` 打在按钮上时 recurse 回 `reduce(state, action.command, ...)`。** 不是第二份 delete
  实现,是同一份的第二个入口。`PanelFocusTests` 逐个动作比对两条路径的 `state` 和 `effect`。
- **只有 delete 清掉按钮焦点**(它换了选中行);pin / expand 保持。
- **顶栏是一条有站点的 band**,站点由 `PanelTab.topBarItems` 推导(`+` 只在提示词页),
  顶栏渲染同一个数组。`←/→` 在标签上**先花在切页上**,切到头才走到 `+` / 齿轮。
- **band 是面板级的,不是标签页级的** —— `SelectionReducer.swapTab` 是那条规则。
- **`reconcile` 的顺序有坑:** 传进来的 `actions` 描述的是**调用前**那一行。所以只要它挪了
  选中项,按钮焦点必须整个丢掉;而且**只清 row 焦点,不许碰 `.tabs`**。

---

## 5. 数据、加密、撤销

- **Keychain 读取:只有 `errSecItemNotFound` 才能生成新密钥。** 其他任何错误(钥匙串锁定、
  用户拒绝授权、ACL 不匹配)必须向上抛。判断错了会让整个历史被一把新密钥孤儿化,而用户
  只看到一个空面板。`KeychainKeyStoreTests` 覆盖 6 种错误码。
- **`LegacyImporter` 只跑一次,对着用户唯一一份数据。** 只读 v1 文件,永不写/删;解密或解析
  失败必须**中止且不写 marker**,让下次启动重试。改这个文件要格外小心。
- **Schema 版本号必须和迁移同一个事务。** `PRAGMA user_version` 写在 `transaction { }`
  **里面**。写外面时 commit 完、盖章前崩一次,库就带着 v2 的列却自称 v0 —— 下次重跑
  `applyV2`,而 `ALTER TABLE` 不像 v1 的 `CREATE TABLE IF NOT EXISTS` 幂等,一个其实
  完好的库再也打不开。
- **缩略图存行内加密列,不存 sidecar。** 这样"删图必删缩略图"是 schema 的性质。seal 失败
  必须落 `.null` 不是空 `Data()` —— backfill 查 `thumbnail IS NULL`,空 blob 会被当成
  "已经有了",永远补不上。
- **解密失败的行要**标记 `isUnreadable` **并显示出来**,不许渲染成空白行。空行看起来就是
  "app 把我的内容弄丢了"。

### 5.1 撤销必须是真正的逆操作

- **unpin 会重写排序时间戳**,所以撤销要**同时**还原 `is_pinned` 和原时间戳;只还原标志位
  会留下一个位置错乱的条目。
- **`LocalStore.restore` 必须把 sidecar 写回去,不只是插回行。** `delete` 先 `removeBlob`
  删文件;只插回行 = 行有 `blob_path`、缩略图也在(它是列),但展开和粘贴**拿不到图** ——
  这就是 SC-05 换了个机制原样重演。写回要 `cipher.seal`,`content` 列放预览标签而不是图片。
- **缺字节抛 `RestoreFailure.missingImageData`,抛在插行之前**,不许留一个假装有图的行。
- **撤销失败要把条目放回栈里。** 无条件 `removeFirst` 会让用户同时失去那一行和唯一的退路。

### 5.2 pin / unpin 的排序语义

- **unpin 必须把条目提到未 pin 组顶部**(重写 `created_at`/`updated_at`)。保留旧时间戳会让它
  落进**最旧的未 pin 行**里,接下来几次捕获就淘汰掉它 —— unpin 会变成**延迟删除**
  (线上真实发生过,靠 `swilclip-recover` 从 v1 找回)。
- **pin 方向不改时间戳**:pinned 组小到能扫,年龄就是它的排序依据。
- **pin/unpin 后必须 bump `AppModel.reorderToken`。** 条目 id 没变、只有位置变,
  `onChange(of: selectedID)` 不会触发,选中行会被留在视野外。

---

## 6. UI —— `docs/ui-design.md` 是 canonical

- **一律走 `Design/Tokens.swift`**,不许硬编码颜色/间距/圆角/字号。§7 的数值是用户 A/B 过的。
- **尺寸走 `@Environment(\.metrics)`**,不要直接读 `Token` 的尺寸/字号。字号是**乘点数**
  而非 `scaleEffect`(后者会重采样导致文字发虚)。hairline 恒为 0.5pt。
- **列表滚动只走 `ScrollAnchoring`,一律 `anchor: nil`。** 规则是"选中行在舒适区内一格都不滚,
  逼近边缘才最小幅度滚,保留 2 行余量;键盘滚动不加动画"。**不要用 `anchor: .center`** ——
  那会让列表在每次按键时整体位移,而且动画会在按住方向键时叠成拖影。
- **scrim 必须画在玻璃「上面」。** `.background(glass).background(tint)` 会把底色叠到
  `.behindWindow` 效果**下面**,vibrancy 视图自己画一层模糊背景把它整个盖住 —— 底色等于不存在。
  **这才是"亮色 App 透过来盖不住"的原因**,不是模糊不够。现在是 `ZStack { glass; scrim }`,
  两个 sheet 同理。
- **深色数值一个都不许动**;浅色是**按角色重写**的,不是把明度绕 50 翻转(翻转出来的灰是脏的)。
- **`Token.Accent` 已删除,不许加回来。** 主题色是用户偏好,只能走 `@Environment(\.theme)`。
  只开放**色相**,饱和度 84 / 明度 62(深)48(浅)锁死。`onAccent` **必须算**
  (WCAG 相对亮度),不许写死白色 —— 白字在柠檬绿上读不出来。
- 设置面板根部要有 `.tint(theme.accent)`,否则原生控件跟的是**系统**强调色。

---

## 7. 品牌 / 标识符 —— 一个能改,一个不能

- **用户看得见的名字只写在一处**:`swift/scripts/bundle.sh` 的 `PRODUCT_NAME`。它写进
  `CFBundleName`,运行时由 `Brand.name` 读回来。**改名 = 改这一行 + 重新打包。**
  代码里不许再出现 `"SwilClip"` 字面量(`Brand.fallbackName` 除外)。
- **`CFBundleIdentifier`(`com.supwilsoft.swilclip.swift`)和数据目录(`SwilClipSwift`)
  必须冻结。** 加密密钥的钥匙串 ACL、`UserDefaults` domain、`SMAppService` 登录项注册
  全以 bundle id 为键;改了就丢密钥,丢密钥**所有加密行都读不回来**。用户永远看不到它们。
- `TARGET_NAME` 是 SPM product 名,和 `Package.swift` 对齐即可。

---

## 8. 中英文 —— 打不散的字符串目录

- 全部 UI 文案在 `SwilClipCore/Localization/Strings.swift`,每条一行 `pick(english, chinese)`。
  **故意不用 `.lproj` / `String(localized:)`**:那条路跟随*系统*语言,而这里要应用内可切换;
  硬做只能手动加载 `.lproj` bundle,缺翻译还会把 key 漏到屏幕上。现在缺翻译是**编译错误**。
- 加文案就加一个 property,两种语言必须同时给。**不要**引入 key→value 查表。
- 中文用全角标点。视图从 `@Environment(\.strings)` 取。
- 设置面板和提示词编辑器是**独立的 `NSHostingView`**,拿不到 panel 的 environment,所以由
  `Localized` 包一层(它在自己的 `body` 里读 `settings.strings` / `settings.theme`,才是响应式的)。
  浅色/深色**不用**从这里传 —— 它挂在 `NSApp.appearance` 上,每个窗口自动继承。
- **不需要 `onLanguageChange`。** `@Observable` 已覆盖 SwiftUI;唯一的 AppKit 界面(菜单栏菜单)
  每次打开都重建。加个没人订阅的 hook 就是死代码。

### 8.1 快捷键说明书 —— 不许手写第二份

`ShortcutReference` 是**结构**(动作、分组、按哪个键),`Strings` 是**文案**,设置页只是渲染。
两条硬性保证:

- `KeyCommand.documentedAction` 是**穷举 switch**:加 case 而不给它在说明书里安排位置,**编译不过**。
- 可改键(唤出快捷键、切换标签页键)由调用方传进去,不是常量 —— 印在键帽上的和真正生效的
  **不可能不一致**。

---

## 9. 壳层接线 —— 规则写了,线也要接上

Core 的规则再漂亮,壳层漏接一根线就等于没有。**已经踩过的四处:**

- **设置里改唤出快捷键,必须重新 `RegisterEventHotKey`**(走 `Settings.onHotkeyChange`)。
  否则键帽变了、生效的还是旧组合 —— 设置界面在撒谎。注册失败要写回 `hotkeyIsRegistered`
  并显示在**那个输入框下面**,只 NSLog 等于没说。
- **菜单栏「设置…」要开设置,不是开面板**(走 `PanelController.showSettings()`,sheet 挂在
  面板上所以得先 `show()`)。
- **面板尺寸改了要当场 resize**(走 `Settings.onPanelSizeChange`)。`show()` 里的对齐只覆盖
  "关着的时候改",而尺寸控件在面板自己的 sheet 里。
- **undo 跨 tab 要走 `swapTabState`**,不许直接 `selection.tab = tab` —— 那会跳过 query /
  搜索态的存取,把当前页的搜索拖到另一边。
- **登录项状态不许缓存。** `SMAppService.mainApp.status` 是唯一真相,每次读实时值。

**教训**:Core 有测试而壳层没有,所以壳层的错只能靠**接线级冒烟**发现。改任何 `on*Change`
回调或菜单项时,手动走一遍那条路径。

---

## 10. Git 与发布

- **不要自动 commit / push**(见 §0)。
- `.githooks/pre-push` 每次 push 前跑两棵树的门禁:
  - `swift/` → `swift test`(220 测试,无 GUI,约 0.15s)
  - `tauri/` → `pnpm prepush`(typecheck + lint + test + cargo test),让冻结的存档不会烂掉
- 刻意**不含** release 构建与公证(重、平台相关),留给手动。紧急绕过:`git push --no-verify`。
- 发布流程见 [docs/releasing.md](docs/releasing.md)。凭据在仓库根的 `.env.release`(已 gitignore)。
- 本地迭代用 `bundle.sh --release`(约 13s,Developer ID 签名)。**debug 构建跑不起来** ——
  ad-hoc 签名和加密密钥的钥匙串 ACL 不匹配,会弹密码框。公证只有分发给别人时才需要。
