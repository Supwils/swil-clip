import AppKit
import Carbon.HIToolbox
import SwiftUI
import SwilClipCore

/// Preferences, and the manual.
///
/// ## Why the shortcut list lives in here
///
/// A keyboard-first panel that hides its keyboard is a keyboard-second panel.
/// The footer reel shows four hints and drops two of them at Small; everything
/// else — `p`, `d`, `e`, `⇧S`, `⌘↑`, type-to-find — was previously discoverable
/// only by reading the source. This sheet is the one place a user already opens
/// on purpose, so it is where the rest of the app explains itself.
///
/// The list is not written here. It comes from ``ShortcutReference``, with the
/// two rebindable keys substituted from the live settings, so a printed keycap
/// cannot disagree with the key that actually works.
struct SettingsView: View {
    @Bindable var settings: Settings
    let onClose: () -> Void

    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case shortcuts
        var id: String { rawValue }
    }

    /// Shared with the window ``PanelController`` builds for this view, so the
    /// sheet and its contents cannot disagree about how big they are.
    static let preferredSize = CGSize(width: 460, height: 620)

    @State private var pane: Pane = .general
    @State private var isRecordingHotkey = false
    @State private var isRecordingTabKey = false
    /// Read live from the system on appear and after every toggle — never cached
    /// across a settings session, because System Settings can change it.
    @State private var loginItemState = LoginItem.state
    @State private var loginItemError: String?
    @State private var isTrustedForAutoPaste = AccessibilityPermission.isTrusted

    private var strings: Strings { settings.strings }
    private var theme: Theme { settings.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch pane {
                    case .general: generalPane
                    case .shortcuts: ShortcutSheet(settings: settings)
                    }
                }
                .padding(Token.Space.edge + 4)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            Hairline()
            footer
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        // Same stacking rule as AppShell: the tint has to be *over* the
        // vibrancy view, or a bright window behind the sheet shows through it.
        .background {
            ZStack {
                VisualEffectBackground(material: .sheet, cornerRadius: 0)
                Token.Surface.popover
            }
        }
        .environment(\.strings, strings)
        .environment(\.theme, theme)
        // AppKit controls default to the *system* accent, which leaves a sheet
        // full of blue segmented pickers sitting under a swatch row the user
        // just set to lime. One tint at the root pushes the choice into every
        // native control the sheet contains.
        .tint(theme.accent)
        .onAppear {
            isTrustedForAutoPaste = AccessibilityPermission.isTrusted
            loginItemState = LoginItem.state
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(strings.settingsTitle)
                .font(Token.Typography.sectionLabel)
                .foregroundStyle(Token.Foreground.primary)
            Spacer(minLength: 0)
            Picker("", selection: $pane) {
                Text(strings.paneGeneral).tag(Pane.general)
                Text(strings.paneShortcuts).tag(Pane.shortcuts)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Token.Space.edge + 4)
        .padding(.vertical, 12)
    }

    // MARK: - General

    @ViewBuilder
    private var generalPane: some View {
        // Look and feel first — and the language switch first of all, since
        // someone hunting for it is someone who cannot read the labels below.
        languageSection
        appearanceSection
        accentSection
        panelSizeSection
        panelTintSection
        // Then behaviour.
        hotkeySection
        tabSwitchSection
        historySection
        autoPasteSection
        launchAtLoginSection
    }

    private var languageSection: some View {
        section(strings.languageSection, hint: strings.languageHint) {
            Picker("", selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(strings.languageOption(language)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var appearanceSection: some View {
        section(strings.appearanceSection, hint: strings.appearanceHint) {
            Picker("", selection: $settings.appearance) {
                ForEach(Appearance.allCases) { appearance in
                    Text(strings.appearanceOption(appearance)).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var accentSection: some View {
        section(strings.accentSection, hint: strings.accentHint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(AccentPalette.presets) { preset in
                        AccentSwatch(
                            hue: preset.hue,
                            isSelected: isSelected(preset.hue),
                            action: { settings.accentHue = preset.hue }
                        )
                    }
                    Spacer(minLength: 0)
                }
                HueSlider(hue: $settings.accentHue)
            }
        }
    }

    /// Presets are exact hues, but the slider produces fractional ones. Half a
    /// degree is well inside "the same colour", and without the tolerance the
    /// swatch ring would drop off after a one-pixel drag.
    private func isSelected(_ hue: Double) -> Bool {
        abs(AccentPalette.normalized(settings.accentHue) - hue) < 0.5
    }

    private var panelTintSection: some View {
        section(strings.panelTintSection, hint: strings.panelTintHint) {
            Picker("", selection: $settings.panelTint) {
                ForEach(PanelTint.allCases) { tint in
                    Text(strings.panelTintOption(tint)).tag(tint)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var hotkeySection: some View {
        section(strings.summonSection, hint: strings.summonHint) {
            VStack(alignment: .leading, spacing: 6) {
            HStack {
                shortcutField(settings.hotkey.displayString, isRecording: isRecordingHotkey)
                Spacer()
                Button(isRecordingHotkey ? strings.pressKeys : strings.change) {
                    isRecordingHotkey.toggle()
                }
                .buttonStyle(.plain)
                .font(Token.Typography.meta)
                .foregroundStyle(theme.accent)
            }
            .background {
                if isRecordingHotkey {
                    KeyRecorder { code, modifiers in
                        settings.hotkey = .init(
                            keyCode: UInt32(code), modifiers: carbonModifiers(modifiers)
                        )
                        isRecordingHotkey = false
                    }
                }
            }
            // Registration is attempted the moment the binding changes, so this
            // appears under the field the user just typed into — which is the
            // only place they will look when the shortcut does nothing.
            if !settings.hotkeyIsRegistered {
                notice(strings.summonTaken)
            }
            }
        }
    }

    private var panelSizeSection: some View {
        section(strings.panelSizeSection, hint: strings.panelSizeHint) {
            Picker("", selection: $settings.panelSize) {
                ForEach(PanelSize.allCases) { size in
                    Text("\(size.label(strings))  \(size.dimensionLabel)")
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var tabSwitchSection: some View {
        section(strings.switchTabsSection, hint: strings.switchTabsHint) {
            HStack {
                shortcutField(
                    settings.tabSwitchKey.displayString,
                    isRecording: isRecordingTabKey,
                    minWidth: 44
                )
                Spacer()
                if settings.tabSwitchKey != .tab {
                    Button(strings.reset) { settings.tabSwitchKey = .tab }
                        .buttonStyle(.plain)
                        .font(Token.Typography.meta)
                        .foregroundStyle(Token.Foreground.subtle)
                }
                Button(isRecordingTabKey ? strings.pressAKey : strings.change) {
                    isRecordingTabKey.toggle()
                }
                .buttonStyle(.plain)
                .font(Token.Typography.meta)
                .foregroundStyle(theme.accent)
            }
            .background {
                if isRecordingTabKey {
                    // Unlike the global hotkey, this one is matched in pure code
                    // rather than registered with Carbon, so a bare key is fine.
                    KeyRecorder(requiresModifier: false) { code, modifiers in
                        settings.tabSwitchKey = KeyBinding(keyCode: code, modifiers: modifiers)
                        isRecordingTabKey = false
                    }
                }
            }
        }
    }

    private var historySection: some View {
        section(strings.historySection, hint: strings.historyHint) {
            Picker("", selection: $settings.historyLimit) {
                ForEach(Settings.historyLimitChoices, id: \.self) { choice in
                    Text("\(choice)").tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var autoPasteSection: some View {
        section(
            strings.autoPasteSection,
            hint: settings.autoPaste ? strings.autoPasteHintOn : strings.autoPasteHintOff
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: autoPasteBinding) {
                    Text(strings.autoPasteToggle)
                        .font(Token.Typography.body)
                        .foregroundStyle(Token.Foreground.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                // Closes SC-06. v1 posted the synthetic ⌘V regardless, reported
                // success and pasted nothing, with no way to find out why.
                if settings.autoPaste && !isTrustedForAutoPaste {
                    notice(strings.autoPasteNeedsAccessibility) {
                        Button(strings.openSystemSettings) {
                            AccessibilityPermission.openSettings()
                        }
                        .buttonStyle(.plain)
                        .font(Token.Typography.meta)
                        .foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }

    /// Turning Auto Paste on triggers the permission prompt immediately, so the
    /// user learns about the requirement at the moment they opt in — not the
    /// first time a paste silently fails.
    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { settings.autoPaste },
            set: { newValue in
                settings.autoPaste = newValue
                guard newValue else { return }
                isTrustedForAutoPaste = AccessibilityPermission.request()
            }
        )
    }

    private var launchAtLoginSection: some View {
        section(strings.loginSection, hint: strings.loginHint) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: loginItemBinding) {
                    Text(strings.loginToggle(Brand.name))
                        .font(Token.Typography.body)
                        .foregroundStyle(Token.Foreground.primary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!LoginItem.isInstalledInApplications)

                if !LoginItem.isInstalledInApplications {
                    notice(strings.loginNeedsApplicationsFolder(Brand.name))
                } else if loginItemState == .requiresApproval {
                    notice(strings.loginNeedsApproval) {
                        Button(strings.openLoginItems) { LoginItem.openSystemSettings() }
                            .buttonStyle(.plain)
                            .font(Token.Typography.meta)
                            .foregroundStyle(theme.accent)
                    }
                } else if let loginItemError {
                    notice(loginItemError)
                }
            }
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemState.isOn },
            set: { wanted in
                loginItemError = nil
                switch LoginItem.set(wanted) {
                case .success(let state):
                    // Read back rather than assume: register() can succeed and
                    // still land in requiresApproval.
                    loginItemState = state
                case .failure(let error):
                    loginItemError = error.localizedDescription
                    loginItemState = LoginItem.state
                }
            }
        )
    }

    private var footer: some View {
        HStack {
            Text(Brand.nameAndVersion)
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.faint)
            Spacer()
            Button(strings.done, action: onClose)
                .buttonStyle(.plain)
                .font(Token.Typography.body)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    theme.accent,
                    in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                )
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Token.Space.edge + 4)
        .padding(.vertical, 12)
    }

    // MARK: - Building blocks

    private func section(
        _ title: String,
        hint: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeading(title)
            content()
            Text(hint)
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortcutField(
        _ label: String,
        isRecording: Bool,
        minWidth: CGFloat? = nil
    ) -> some View {
        Text(label)
            .font(Token.Typography.rowMono)
            .foregroundStyle(Token.Foreground.primary)
            .frame(minWidth: minWidth)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Token.Surface.sunk,
                in: RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Token.Radius.md, style: .continuous)
                    .strokeBorder(
                        isRecording ? theme.accentRing : Token.Border.subtle,
                        lineWidth: isRecording ? 1 : 0.5
                    )
            }
    }

    private func notice(
        _ text: String,
        @ViewBuilder action: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Token.Status.destructive)
            Text(text)
                .font(Token.Typography.meta)
                .foregroundStyle(Token.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
        .padding(7)
        .background(
            Token.Status.destructiveSoft,
            in: RoundedRectangle(cornerRadius: Token.Radius.sm, style: .continuous)
        )
    }
}

// MARK: - Shortcut reference

/// The manual pane: every way to drive the app, grouped by when you would want
/// it, with the live bindings printed on the keycaps.
private struct ShortcutSheet: View {
    let settings: Settings
    @Environment(\.strings) private var strings

    /// Wide enough for `⌘⇧V` and `A–Z`, narrow enough to leave the description
    /// column room for a Chinese sentence at 460 pt.
    private let keyColumn: CGFloat = 66

    private var sections: [ShortcutSection] {
        ShortcutReference.sections(
            summon: settings.hotkey.displayString,
            tabSwitch: settings.tabSwitchKey.displayString
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    GroupHeading(strings.title(for: section.group))
                    ForEach(section.entries) { entry in
                        row(entry)
                    }
                }
            }
        }
    }

    private func row(_ entry: ShortcutEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark(entry)
                .frame(width: keyColumn, alignment: .leading)
            Text(strings.label(for: entry.action))
                .font(Token.Typography.body)
                .foregroundStyle(Token.Foreground.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func mark(_ entry: ShortcutEntry) -> some View {
        if let symbol = entry.symbol {
            // Not a keystroke. A glyph says so at a glance, where an empty
            // column would only look like a missing value.
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Token.Foreground.faint)
                .frame(minWidth: 20, minHeight: 20)
        } else {
            HStack(spacing: 2) {
                ForEach(entry.keys, id: \.self) { Keycap(label: $0) }
            }
        }
    }
}

/// One preset colour chip.
private struct AccentSwatch: View {
    let hue: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.swatch(hue: hue))
                .frame(width: 20, height: 20)
                .overlay {
                    // The ring sits *outside* the chip rather than on it, so
                    // selecting a swatch does not shrink the colour you are
                    // trying to judge.
                    Circle()
                        .strokeBorder(Token.Foreground.primary, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(isSelected ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(3)
    }
}

/// A hue spectrum with a draggable thumb.
///
/// A stock `Slider` would work and would say nothing: hue is the one value
/// where the control can show you the whole answer space at once. The track is
/// drawn from the same ``Theme/swatch(hue:)`` the chips use, so it is a preview
/// rather than an illustration.
private struct HueSlider: View {
    @Binding var hue: Double

    /// Every 20° — enough stops that the interpolation between them is
    /// imperceptible, few enough that the gradient stays cheap.
    private static let stops: [Color] = stride(from: 0.0, through: 360.0, by: 20)
        .map { Theme.swatch(hue: $0) }

    private let thumb: CGFloat = 15

    var body: some View {
        GeometryReader { geometry in
            let track = max(1, geometry.size.width)
            let position = CGFloat(AccentPalette.normalized(hue) / 360) * track

            Capsule()
                .fill(
                    LinearGradient(
                        colors: Self.stops, startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(height: 8)
                .frame(maxHeight: .infinity)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(Theme.swatch(hue: hue))
                        .frame(width: thumb, height: thumb)
                        .overlay {
                            Circle().strokeBorder(.white, lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
                        // Clamped so the thumb stays inside the track at both
                        // ends instead of hanging off the rounded cap.
                        .offset(x: min(max(position - thumb / 2, 0), track - thumb))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max(value.location.x / track, 0), 1)
                            hue = Double(fraction) * 360
                        }
                )
        }
        .frame(height: thumb)
    }
}

/// The small tracked, upper-cased heading used above every settings group.
private struct GroupHeading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Token.Typography.groupHeading)
            // Letter-spacing an upper-cased Latin label is what makes it read as
            // a heading rather than as shouting. Chinese has no case and no
            // inter-glyph convention to borrow, so it gets none.
            .tracking(text.allSatisfy(\.isASCII) ? 0.9 : 0)
            .foregroundStyle(Token.Foreground.subtle)
    }
}

/// Captures the next key combination.
///
/// Used by both shortcut fields. `requiresModifier` is the difference between
/// them: a global hotkey without a modifier would fire whenever the user typed
/// that letter anywhere, while the in-panel tab key is only ever consulted while
/// the panel has focus, so a bare `⇥` is exactly right there.
private struct KeyRecorder: NSViewRepresentable {
    var requiresModifier: Bool = true
    let onRecord: (UInt16, KeyModifiers) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.requiresModifier = requiresModifier
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    private final class RecorderView: NSView {
        var requiresModifier = true
        var onRecord: ((UInt16, KeyModifiers) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: KeyModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }

            if requiresModifier && modifiers.isEmpty { NSSound.beep(); return }
            // Escape is the way out of every panel; letting it be rebound would
            // strand the user in a mode with no exit.
            if event.keyCode == KeyCode.escape { NSSound.beep(); return }
            onRecord?(event.keyCode, modifiers)
        }
    }
}

/// Carbon modifier mask for the global hotkey, which cannot use ``KeyModifiers``.
private func carbonModifiers(_ modifiers: KeyModifiers) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.command) { result |= UInt32(cmdKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    if modifiers.contains(.option) { result |= UInt32(optionKey) }
    if modifiers.contains(.control) { result |= UInt32(controlKey) }
    return result
}
