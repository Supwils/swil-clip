import Foundation

/// The shell's callbacks, and a way to prove every one of them is connected.
///
/// The four wiring defects that shipped (SW-01, SW-02, SW-06, SW-12) share one
/// shape: a callback nobody set, or set to the wrong thing. They compile, they
/// type-check, and the screen looks fine until the moment the callback should
/// have fired. `CLAUDE.md` §9 used to be a hand-written list of them.
///
/// ``unwired(in:)`` finds callbacks by *reflection*, not from a list, so the
/// test that calls it also covers a callback added next year: nobody has to
/// remember to enrol it. That is the wiring version of the exhaustive switch
/// in `KeyCommand.documentedAction`.
enum Wiring {
    /// Connect the preferences whose effects live outside SwiftUI.
    ///
    /// `AppDelegate` used to do this inline in `applicationDidFinishLaunching`,
    /// between the keychain and the database, where no test could reach it.
    /// - Parameter rebindHotkey: re-register the summon shortcut with Carbon.
    @MainActor
    static func connect(settings: Settings, rebindHotkey: @escaping () -> Void) {
        settings.onAppearanceChange = { $0.apply() }
        // Rebinding in Settings has to reach Carbon, or the field lies (SW-01).
        settings.onHotkeyChange = { _ in rebindHotkey() }
    }

    /// The names of `on…` closure properties on `object` that are still `nil`.
    ///
    /// `@Observable` stores a property `onDismiss` as `_onDismiss`, so the
    /// underscore is stripped before matching and in the result.
    static func unwired(in object: AnyObject) -> [String] {
        callbacks(in: object).filter { !$0.isSet }.map(\.name).sorted()
    }

    /// Every `on…` optional property the reflection sees, set or not. Exposed
    /// so a test can assert the scan found anything at all — a reflection that
    /// silently matched nothing would make ``unwired(in:)`` pass vacuously.
    static func callbacks(in object: AnyObject) -> [(name: String, isSet: Bool)] {
        Mirror(reflecting: object).children.compactMap { child in
            guard var name = child.label else { return nil }
            if name.hasPrefix("_") { name.removeFirst() }
            guard name.hasPrefix("on"), name.dropFirst(2).first?.isUppercase == true else {
                return nil
            }
            let value = Mirror(reflecting: child.value)
            guard value.displayStyle == .optional else { return nil }
            return (name, !value.children.isEmpty)
        }
    }
}
