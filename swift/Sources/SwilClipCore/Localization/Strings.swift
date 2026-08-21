import Foundation

/// Every word the interface says, in both languages.
///
/// ## Shape
///
/// One property per string, each written as `pick(english, chinese)` so the two
/// versions sit on the same line. That is the whole point: a translation cannot
/// go missing, because there is no lookup to miss — the compiler already
/// required both. Renaming a property updates every call site; adding one
/// forces both languages at once.
///
/// It lives in `SwilClipCore` rather than the app target for the same reason
/// the keyboard model does: it is pure data with no window server in it, so the
/// tests can read it.
///
/// ## Rules for the copy itself
///
/// - The Chinese is written, not translated. Where a literal rendering would
///   read like a machine, the sentence is rewritten to say the same thing the
///   way a person would.
/// - Footer hints stay two or three characters wide in Chinese. The panel is
///   340 pt and the hint reel degrades by dropping labels; short labels mean it
///   degrades later.
/// - Keycaps (`⏎`, `⇧S`, `⌘V`) are never translated. They are what is printed
///   on the hardware.
public struct Strings: Sendable, Equatable {
    public let language: ResolvedLanguage

    public init(_ language: ResolvedLanguage) {
        self.language = language
    }

    public init(_ language: AppLanguage, preferring preferredLanguages: [String] = Locale.preferredLanguages) {
        self.init(language.resolved(preferring: preferredLanguages))
    }

    private func pick(_ english: String, _ chinese: String) -> String {
        language == .chinese ? chinese : english
    }

    // MARK: - Panel chrome

    public var clipboardTab: String { pick("Clipboard", "剪贴板") }
    public var promptsTab: String { pick("Prompts", "提示词") }
    public var settingsTooltip: String { pick("Settings", "设置") }
    public var newPromptTooltip: String { pick("New prompt (n)", "新建提示词 (n)") }
    /// Compact verb for the footer while a top-bar stop is focused.
    public func topBarLabel(_ item: TopBarItem) -> String {
        switch item {
        case .tabs: pick("open", "进入")
        case .newPrompt: pick("new", "新建")
        case .settings: pick("settings", "设置")
        }
    }
    public var searchHistoryPlaceholder: String { pick("Search history", "搜索历史") }
    public var searchPromptsPlaceholder: String { pick("Search prompts", "搜索提示词") }
    public var dividerRecent: String { pick("Recent", "最近") }
    public var dividerLibrary: String { pick("Library", "提示词库") }
    public var dismiss: String { pick("Dismiss", "关闭") }

    // MARK: - Empty states

    public var emptyNoMatchesTitle: String { pick("No matches", "没有匹配项") }
    public var emptyNoMatchesHint: String {
        pick("Try a shorter query, or press esc to clear it.", "换个更短的关键词，或按 esc 清空。")
    }
    public var emptyClipsTitle: String { pick("Nothing copied yet", "还没有复制过东西") }
    public var emptyClipsHint: String {
        pick("Copy something and it will appear here.", "随便复制点什么，它就会出现在这里。")
    }
    public var emptyPromptsTitle: String { pick("No prompts yet", "还没有提示词") }
    public var emptyPromptsHint: String {
        pick(
            "Press n to write one, or ⇧S on a clipboard entry to save it here.",
            "按 n 新建一条，或在剪贴板条目上按 ⇧S 存进来。"
        )
    }

    // MARK: - Footer hint reel
    //
    // Kept short in both languages; the reel drops labels before it truncates.

    public var hintMove: String { pick("move", "移动") }
    public var hintPaste: String { pick("paste", "粘贴") }
    public var hintCopy: String { pick("copy", "复制") }
    // "存词库" rather than "存提示词": three characters keeps the full hint reel
    // inside 340 pt, and 词库 is already the word the pinned divider uses.
    public var hintSaveAsPrompt: String { pick("save", "存词库") }
    public var hintNew: String { pick("new", "新建") }
    public var hintUndo: String { pick("undo", "撤销") }
    public var hintFind: String { pick("find", "搜索") }
    public var hintCancel: String { pick("cancel", "取消") }
    public var hintSave: String { pick("save", "保存") }

    // MARK: - Row actions

    public var pin: String { pick("Pin", "置顶") }
    public var unpin: String { pick("Unpin", "取消置顶") }
    public var expand: String { pick("Expand", "展开") }
    public var collapse: String { pick("Collapse", "收起") }
    public var preview: String { pick("Preview", "预览") }
    public var edit: String { pick("Edit", "编辑") }
    public var delete: String { pick("Delete", "删除") }
    /// Compact verb for the footer, shown next to `⏎` while a button is focused
    /// so the user can always see what Return is currently aimed at.
    public func rowActionLabel(_ action: RowAction) -> String {
        switch action {
        case .pin: pick("pin", "置顶")
        case .promote: pick("save", "存词库")
        case .edit: pick("edit", "编辑")
        case .expand: pick("expand", "展开")
        case .delete: pick("delete", "删除")
        }
    }
    public var hintBack: String { pick("back", "返回") }
    public var hintOpen: String { pick("open", "进入") }
    public var hintSwitch: String { pick("switch", "切换") }

    /// Shown in place of a preview whose ciphertext would not open.
    public var unreadableRow: String {
        pick("Could not decrypt this entry", "这一条解密失败")
    }

    public var saveAsPromptTooltip: String { pick("Save as prompt (⇧S)", "存为提示词 (⇧S)") }

    public func characterCount(_ count: Int) -> String {
        pick(count == 1 ? "1 character" : "\(count) characters", "\(count) 字")
    }

    // MARK: - Prompt editor

    public var newPromptTitle: String { pick("New prompt", "新建提示词") }
    public var editPromptTitle: String { pick("Edit prompt", "编辑提示词") }
    public var fieldTitle: String { pick("Title", "标题") }
    public var fieldBody: String { pick("Prompt", "正文") }
    public var titlePlaceholder: String { pick("Named from the first line", "默认取正文第一行") }
    public var cancel: String { pick("Cancel", "取消") }
    public var save: String { pick("Save", "保存") }
    public var done: String { pick("Done", "完成") }
    public var quit: String { pick("Quit", "退出") }

    // MARK: - Status line

    public var statusOnlyTextPromotes: String {
        pick("Only text can become a prompt", "只有文本能存为提示词")
    }
    public func statusSavedAsPrompt(_ title: String) -> String {
        pick("Saved as prompt · \(title)", "已存为提示词 · \(title)")
    }
    public var statusPinRestored: String { pick("Pin restored", "已恢复置顶") }
    public var statusUnpinnedAgain: String { pick("Unpinned again", "已重新取消置顶") }

    public func errorReadHistory(_ detail: String) -> String {
        pick("Could not read history: \(detail)", "读取历史失败：\(detail)")
    }
    public func errorRecordClip(_ detail: String) -> String {
        pick("Could not record clip: \(detail)", "记录剪贴板失败：\(detail)")
    }
    public func errorReadEntry(_ detail: String) -> String {
        pick("Could not read that entry: \(detail)", "读取该条目失败：\(detail)")
    }
    public func errorDelete(_ detail: String) -> String {
        pick("Could not delete: \(detail)", "删除失败：\(detail)")
    }
    public func errorPin(_ detail: String) -> String {
        pick("Could not pin: \(detail)", "置顶失败：\(detail)")
    }
    public func errorPromote(_ detail: String) -> String {
        pick("Could not save as prompt: \(detail)", "存为提示词失败：\(detail)")
    }
    public func errorClear(_ detail: String) -> String {
        pick("Could not clear: \(detail)", "清空失败：\(detail)")
    }
    public func errorUndo(_ detail: String) -> String {
        pick("Could not undo: \(detail)", "撤销失败：\(detail)")
    }
    public func errorSavePrompt(_ detail: String) -> String {
        pick("Could not save prompt: \(detail)", "保存提示词失败：\(detail)")
    }

    // MARK: - Menu bar

    public func menuShow(_ appName: String) -> String {
        pick("Show \(appName)", "显示\(appName)")
    }
    public var menuSettings: String { pick("Settings…", "设置…") }
    public func menuQuit(_ appName: String) -> String {
        pick("Quit \(appName)", "退出\(appName)")
    }

    // MARK: - Fatal alert

    public func fatalTitle(_ appName: String) -> String {
        pick("\(appName) cannot start", "\(appName) 无法启动")
    }
    public func fatalBody(_ appName: String, detail: String) -> String {
        pick(
            """
            \(detail)

            History is encrypted with a key in your login Keychain. If the \
            Keychain was locked or access was denied, unlock it and reopen \
            \(appName) — no existing data has been changed.
            """,
            """
            \(detail)

            历史记录由登录钥匙串里的密钥加密。如果钥匙串被锁定或访问被拒绝，\
            解锁后重新打开 \(appName) 即可——现有数据没有被改动。
            """
        )
    }

    // MARK: - Settings

    public var settingsTitle: String { pick("Settings", "设置") }
    public var paneGeneral: String { pick("General", "通用") }
    public var paneShortcuts: String { pick("Shortcuts", "快捷键") }
    public var change: String { pick("Change", "修改") }
    public var reset: String { pick("Reset", "恢复默认") }
    public var pressKeys: String { pick("Press keys…", "按下组合键…") }
    public var pressAKey: String { pick("Press a key…", "按下按键…") }
    public var openSystemSettings: String { pick("Open Settings", "打开系统设置") }
    public var openLoginItems: String { pick("Open Login Items", "打开登录项") }

    public var languageSection: String { pick("Language", "语言") }
    public var languageHint: String {
        pick(
            "Applies immediately, everywhere — no restart.",
            "立即生效，全局切换，无需重启。"
        )
    }
    public func languageOption(_ language: AppLanguage) -> String {
        switch language {
        case .system: return pick("System", "跟随系统")
        // Never picked: an English speaker looking for English should not have
        // to recognise 英文, and the same in reverse.
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    public var appearanceSection: String { pick("Appearance", "外观") }
    public var appearanceHint: String {
        pick(
            "The panel floats over whatever you are working in, so following the "
                + "Mac is the safe default — but a dark panel over a light app reads "
                + "as \u{201C}on top of your work\u{201D} rather than part of it.",
            "面板浮在你正在用的 App 上面，所以跟随系统最稳妥——不过浅色 App 上盖一块深色面板，"
                + "会更像「浮在你的工作之上」而不是它的一部分。"
        )
    }
    public func appearanceOption(_ appearance: Appearance) -> String {
        switch appearance {
        case .system: pick("System", "跟随系统")
        case .light: pick("Light", "浅色")
        case .dark: pick("Dark", "深色")
        }
    }

    public var accentSection: String { pick("Accent colour", "主题色") }
    public var accentHint: String {
        pick(
            "One colour, and it only ever means \u{201C}this row is selected\u{201D}. "
                + "Saturation and brightness are fixed so any hue you pick still reads "
                + "as an accent rather than as decoration.",
            "整个界面只有这一种颜色，而且它只表示「这一行被选中了」。饱和度和明度是固定的，"
                + "所以你挑任何色相它都还是重点色，不会变成装饰。"
        )
    }
    public var accentCustomHue: String { pick("Custom hue", "自定义色相") }

    public var panelTintSection: String { pick("Panel opacity", "面板通透度") }
    public var panelTintHint: String {
        pick(
            "How much of the app behind shows through the glass. macOS has no "
                + "\u{201C}blur harder\u{201D} setting — this is the panel\u{2019}s own tint, "
                + "and it is what keeps text readable over a bright window.",
            "背后的 App 能透过玻璃露出多少。macOS 没有「把模糊调大」这个开关——"
                + "这里调的是面板自己的底色，也正是它保证文字在亮色窗口上仍然看得清。"
        )
    }
    public func panelTintOption(_ tint: PanelTint) -> String {
        switch tint {
        case .sheer: pick("Sheer", "通透")
        case .standard: pick("Standard", "标准")
        case .solid: pick("Solid", "厚重")
        }
    }

    public var summonSection: String { pick("Summon shortcut", "唤出快捷键") }
    public var summonTaken: String {
        pick(
            "Another app already owns this combination — the panel will not open on it.",
            "这个组合键已经被别的 App 占用了，面板不会因为它打开。"
        )
    }
    public var summonHint: String {
        pick("Opens the panel wherever the cursor is.", "在光标所在的位置打开面板。")
    }

    public var panelSizeSection: String { pick("Panel size", "面板尺寸") }
    public var panelSizeHint: String {
        pick(
            "Scales the whole panel — text and spacing together, not just the "
                + "window. 340 pt is comfortable on a laptop and cramped on a 5K display.",
            "整体缩放面板——文字和间距一起放大，不只是窗口。340 pt 在笔记本上刚好，在 5K 屏上偏挤。"
        )
    }
    // `PanelSize` lives in the app target (it carries CoreGraphics dimensions),
    // so these are three properties rather than one function over the enum. The
    // switch that pairs them up is next to the enum, where a new case breaks it.
    public var panelSizeSmall: String { pick("Small", "小") }
    public var panelSizeMedium: String { pick("Medium", "中") }
    public var panelSizeLarge: String { pick("Large", "大") }

    public var switchTabsSection: String { pick("Switch tabs", "切换标签页") }
    public var switchTabsHint: String {
        pick(
            "Moves between Clipboard and Prompts. Rebind if an input method "
                + "already claims ⇥, or if a chord suits your hands better.",
            "在「剪贴板」和「提示词」之间切换。如果输入法已经占用了 ⇥,或者你更习惯组合键，可以改。"
        )
    }

    public var historySection: String { pick("History size", "历史条数") }
    public var historyHint: String {
        pick(
            "Pinned entries never count toward this and are never evicted.",
            "置顶条目不计入上限，也永远不会被清掉。"
        )
    }

    public var autoPasteSection: String { pick("Auto Paste", "自动粘贴") }
    public var autoPasteHintOn: String {
        pick(
            "⏎ writes the clipboard, restores focus, then presses ⌘V for you.",
            "⏎ 写入剪贴板、恢复焦点，然后替你按下 ⌘V。"
        )
    }
    public var autoPasteHintOff: String {
        pick(
            "⏎ writes the clipboard and restores focus. You press ⌘V yourself.",
            "⏎ 写入剪贴板并恢复焦点，⌘V 由你自己按。"
        )
    }
    public var autoPasteToggle: String { pick("Paste automatically on ⏎", "按 ⏎ 时自动粘贴") }
    public var autoPasteNeedsAccessibility: String {
        pick("Needs Accessibility permission to send ⌘V.", "需要「辅助功能」权限才能发送 ⌘V。")
    }

    public var loginSection: String { pick("Start at login", "开机自启") }
    public var loginHint: String {
        pick(
            "A clipboard manager that is not running is not failing loudly — "
                + "it is silently not recording.",
            "剪贴板管理器没在运行时不会报错，它只是悄悄地什么都没记下来。"
        )
    }
    public func loginToggle(_ appName: String) -> String {
        pick("Open \(appName) when I log in", "登录时打开 \(appName)")
    }
    public func loginNeedsApplicationsFolder(_ appName: String) -> String {
        pick(
            "Move \(appName) to your Applications folder first — macOS will not "
                + "register a login item from anywhere else.",
            "先把 \(appName) 移到「应用程序」文件夹——macOS 不会为其他位置的 App 注册登录项。"
        )
    }
    public var loginNeedsApproval: String {
        pick("macOS needs you to approve this.", "macOS 需要你手动允许。")
    }

    // MARK: - Shortcut reference

    public func title(for group: ShortcutGroup) -> String {
        switch group {
        case .global: return pick("Anywhere", "任何地方")
        case .navigate: return pick("Moving around", "移动光标")
        case .act: return pick("The selected row", "操作选中行")
        case .search: return pick("Searching", "搜索")
        case .prompts: return pick("Prompts", "提示词")
        case .mouse: return pick("Mouse", "鼠标")
        }
    }

    public func label(for action: ShortcutAction) -> String {
        switch action {
        case .summon:
            return pick("Open the panel at the cursor", "在光标处打开面板")
        case .menuBar:
            return pick(
                "Click the menu-bar icon to open it; right-click for the menu",
                "点菜单栏图标打开，右键出菜单"
            )

        case .moveUp:
            return pick("Select the row above", "选上一行")
        case .moveDown:
            return pick("Select the row below", "选下一行")
        case .moveToFirst:
            return pick("Jump to the first row", "跳到第一行")
        case .moveToLast:
            return pick("Jump to the last row", "跳到最后一行")
        case .switchTab:
            return pick("Switch between Clipboard and Prompts", "在剪贴板和提示词之间切换")
        case .focusTabs:
            return pick(
                "From the first row, reach the bar — then ← → along it",
                "在第一行再按一次就到顶栏——然后用 ← → 沿着它走"
            )

        case .dismiss:
            // Esc peels one layer at a time. Saying so here is the difference
            // between "it did not close" and "it closed what I asked it to".
            return pick(
                "Close the panel — one layer at a time: collapse, leave search, then close",
                "关闭面板——逐层退出：先收起展开，再退出搜索，最后关闭"
            )

        case .confirm:
            return pick(
                "Copy it — and paste, if Auto Paste is on",
                "复制它——开了「自动粘贴」就直接粘上"
            )
        case .toggleExpand:
            return pick("Expand or collapse the full contents", "展开或收起完整内容")
        case .togglePin:
            return pick("Pin it to the top, or unpin it", "置顶，或取消置顶")
        case .deleteItem:
            return pick("Delete it", "删除")
        case .promoteToPrompt:
            return pick("Save a clipboard entry into the prompt library", "把剪贴板条目存进提示词库")
        case .undo:
            return pick("Undo the last delete, pin or unpin", "撤销上一次删除 / 置顶 / 取消置顶")

        case .focusRowActions:
            return pick(
                "Step through the row\u{2019}s buttons: pin, save, expand, delete",
                "在这一行的按钮之间移动：置顶、存词库、展开、删除"
            )
        case .activateRowAction:
            return pick(
                "Run the button you landed on — otherwise ⏎ still copies",
                "运行停在上面的那个按钮——没停在按钮上时 ⏎ 仍然是复制"
            )

        case .beginSearch:
            return pick("Start searching", "开始搜索")
        case .typeToFind:
            return pick("Any other letter starts a search with it", "直接敲任何字母也会进入搜索")
        case .deleteQueryCharacter:
            return pick("Erase one character", "删掉一个字符")
        case .lettersAreTextWhileSearching:
            // The one rule that makes the rest of the keyboard make sense.
            return pick(
                "While searching, letters type instead of running commands",
                "搜索时字母是在打字，不再触发上面那些命令"
            )
        case .clearQuery:
            return pick(
                "Leave search and clear the query",
                "退出搜索并清空关键词"
            )

        case .newPrompt:
            return pick(
                "Write a new prompt — or arrow to + in the bar above",
                "新建一条提示词——也可以用方向键走到上面那个 + 上"
            )
        case .openSettings:
            return pick(
                "Arrow up to the bar, along to the gear, then ⏎",
                "方向键上到顶栏，一路走到齿轮，按 ⏎"
            )
        case .editPrompt:
            return pick(
                "Arrow to the pencil and press ⏎, or click it",
                "用方向键走到铅笔上按 ⏎，或者直接点它"
            )
        case .savePromptEditor:
            return pick("Save and close the editor", "保存并关闭编辑器")
        case .cancelPromptEditor:
            return pick("Discard and close the editor", "放弃修改并关闭编辑器")

        case .clickSelect:
            return pick("Click a row to select it", "单击选中一行")
        case .doubleClickConfirm:
            return pick("Double-click to copy it", "双击直接复制")
        case .rowButtons:
            return pick("Hover a row for pin, expand and delete", "鼠标悬停在行上会出现置顶 / 展开 / 删除")
        case .dragPanel:
            return pick("Drag the dots at the top to move the panel", "拖顶部的三个点可以移动面板")
        }
    }

    // MARK: - Relative time
    //
    // Hand-rolled rather than `DateFormatter`: these render inside a LazyVStack
    // that re-evaluates on every arrow key, and a formatter allocation per row
    // per keypress is exactly the sort of cost that turns into a dropped frame.
    // It is also deterministic, which makes it testable without pinning a
    // system locale.

    private static let englishMonths = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// Compact age for the right-hand column of a row: `now`, `5m`, `3h`, `2d`,
    /// then a date. Short because the column is narrow.
    public func ageLabel(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45:
            return pick("now", "刚刚")
        case ..<3_600:
            let minutes = Int(seconds / 60)
            return pick("\(minutes)m", "\(minutes)分")
        case ..<86_400:
            let hours = Int(seconds / 3_600)
            return pick("\(hours)h", "\(hours)时")
        case ..<604_800:
            let days = Int(seconds / 86_400)
            return pick("\(days)d", "\(days)天")
        default:
            return dateLabel(for: date)
        }
    }

    /// `12 Aug` / `8月12日`.
    public func dateLabel(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day,
              (1...12).contains(month) else { return "" }
        return pick("\(day) \(Self.englishMonths[month - 1])", "\(month)月\(day)日")
    }

    /// Age of a prompt, as a sentence rather than a bare token — the prompt row
    /// has the width for it and "edited" is the part that carries the meaning.
    public func editedLabel(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return pick("edited just now", "刚刚编辑") }
        let age = ageLabel(for: date, now: now)
        if seconds < 604_800 { return pick("edited \(age) ago", "\(age)前编辑") }
        return pick("edited \(age)", "\(age)编辑")
    }
}
