import CryptoKit
import Foundation
import Testing

@testable import SwilClipCore

/// Permanent measurement harness for the panel's full reload.
///
/// The panel reloads *everything* after every clipboard capture — an O(n) read
/// on the hot path. That shape is suspicious given v1's SC-07 was an O(n) write,
/// so it was measured rather than assumed:
///
/// | entries | mean  | worst |
/// |---------|-------|-------|
/// | 50      | 0.13 ms | 0.16 ms |
/// | 500     | 1.20 ms | 1.28 ms |
/// | 1000    | 2.41 ms | 2.58 ms |
///
/// Linear, and irrelevant: 2.4 ms at the largest offered history is a seventh of
/// a frame. **Do not rewrite this into an incremental update** — it would trade
/// a simple, obviously-correct reload for cache-invalidation bugs, and buy
/// nothing a user could perceive.
///
/// Kept rather than deleted so the next person who suspects it can re-run the
/// numbers instead of re-deriving them. Measure in `--release` or not at all:
/// a debug build runs AES roughly 30× slower and will send you rewriting the
/// storage layer for no reason.
@Suite("bench", .disabled("measurement only: swift test -c release --filter reloadCost"))
struct RefreshCostBench {
    @Test("full reload at 50 / 500 / 1000 entries")
    func reloadCost() async throws {
        for count in [50, 500, 1000] {
            let temp = try TempStore()
            let base = Date()
            for index in 0..<count {
                try await temp.store.recordText(
                    "entry \(index) — " + String(repeating: "x", count: 400),
                    limit: count + 10,
                    now: base.addingTimeInterval(Double(index))
                )
            }
            var slowest = 0.0, total = 0.0
            for _ in 0..<10 {
                let start = ContinuousClock.now
                _ = try await temp.store.allClips()
                let elapsed = Double((ContinuousClock.now - start).components.attoseconds) / 1e15
                total += elapsed
                slowest = max(slowest, elapsed)
            }
            print(String(
                format: "  %5d entries → mean %6.2f ms, worst %6.2f ms",
                count, total / 10, slowest
            ))
        }
    }
}
