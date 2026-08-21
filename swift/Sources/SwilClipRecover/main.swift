// recover-from-v1.swift — one-off rescue for entries that exist in the frozen
// v1 history but no longer exist in the v2 database.
//
// Why this exists: the v1 file is never written or deleted, so it stays a
// complete record of everything captured before the migration. If a v2 row is
// lost — evicted, deleted by mistake — the original is still recoverable.
//
// Read-only on v1. Only ever INSERTs into v2, never updates or deletes.
//
// Usage:  swift run swilclip-recover --list-missing-pinned
//         swift run swilclip-recover <clip-id> [<clip-id> …]
//
// macOS asks once for permission to read the history key, because this binary's
// signature differs from the app's. That prompt is the feature working: the key
// is not readable by arbitrary processes.

import Foundation
import SwilClipCore

func run() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            print("usage: recover <clip-id> …  |  recover --list-missing-pinned")
            exit(2)
        }

        do {
            let locations = try StorageLocations.standard()
            let key = try SystemKeychainKeyStore(backend: SystemKeychain()).loadOrCreateKey()
            let cipher = FieldCipher(key: key)
            let store = try LocalStore(locations: locations, key: key)

            guard let legacyURL = locations.legacyHistoryURL,
                  FileManager.default.fileExists(atPath: legacyURL.path)
            else {
                print("✗ no v1 history file to recover from")
                exit(1)
            }

            let document = try Data(contentsOf: legacyURL)
            let decoded = try LegacyImporter().decode(document: document, cipher: cipher)
            print("v1 history holds \(decoded.clips.count) entries")

            let existing = Set(try await store.allClips().map(\.id))

            if arguments == ["--list-missing-pinned"] {
                let missing = decoded.clips.filter {
                    ($0.pinned ?? false) && !existing.contains($0.id)
                }
                print("\(missing.count) pinned entries are in v1 but not in v2:")
                for clip in missing {
                    let date = Date(timeIntervalSince1970: Double(clip.timestamp) / 1000)
                    print("  \(clip.id)  \(date)  \(clip.preview.prefix(48))")
                }
                return
            }

            var restored = 0
            for id in arguments {
                guard let clip = decoded.clips.first(where: { $0.id == id }) else {
                    print("✗ \(id) is not in the v1 history")
                    continue
                }
                guard !existing.contains(id) else {
                    print("• \(id) already present in v2 — left alone")
                    continue
                }
                // Reuses the importer's own insert path, so a recovered row is
                // byte-identical to a migrated one.
                let summary = try await store.importLegacy([clip], limit: Int.max)
                restored += summary.imported
                let date = Date(timeIntervalSince1970: Double(clip.timestamp) / 1000)
                print("✓ restored \(id)  pinned=\(clip.pinned ?? false)  \(date)")
                print("  \(clip.preview.prefix(60))")
            }
        print("\nrestored \(restored) entr\(restored == 1 ? "y" : "ies")")
    } catch {
        print("✗ \(error)")
        exit(1)
    }
}

await run()
