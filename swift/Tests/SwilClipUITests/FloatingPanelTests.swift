import AppKit
import Testing

@testable import SwilClipUI

@Suite("FloatingPanel")
struct FloatingPanelTests {
    @MainActor
    @Test("each summon follows the active Space")
    func followsActiveSpace() {
        let behavior = FloatingPanel.summonCollectionBehavior

        #expect(behavior.contains(.moveToActiveSpace))
        #expect(behavior.contains(.transient))
        #expect(behavior.contains(.fullScreenAuxiliary))
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(!behavior.contains(.stationary))
    }
}
