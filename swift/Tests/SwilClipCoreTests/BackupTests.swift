import Foundation
import Testing

@testable import SwilClipCore

@Suite("BackupSchedule")
struct BackupScheduleTests {
    private let base = Date(timeIntervalSince1970: 1_793_000_000)

    @Test("names round-trip and sort in time order")
    func namesSort() {
        let earlier = BackupSchedule.folderName(for: base)
        let later = BackupSchedule.folderName(for: base.addingTimeInterval(90))
        #expect(earlier < later)
        #expect(BackupSchedule.date(fromFolderName: earlier) == base)
    }

    @Test("due with no backup, or once the newest is a day old")
    func dueness() {
        #expect(BackupSchedule.isDue(latest: nil, now: base))
        #expect(!BackupSchedule.isDue(latest: base, now: base.addingTimeInterval(3_600)))
        #expect(BackupSchedule.isDue(latest: base, now: base.addingTimeInterval(BackupSchedule.interval)))
    }

    @Test("rotation drops the oldest of ours and never touches anything else")
    func rotation() {
        let ours = (0..<9).map { BackupSchedule.folderName(for: base.addingTimeInterval(Double($0) * 86_400)) }
        let names = ours.shuffled() + ["before-upgrade", ".DS_Store", ours[0] + ".partial"]

        let expired = BackupSchedule.expired(names, keep: 7)
        #expect(Set(expired) == Set(ours.prefix(2)))
    }
}

@Suite("LocalStore — backup")
struct LocalStoreBackupTests {
    @Test("a snapshot opens on its own with the same rows")
    func snapshotIsComplete() async throws {
        let temp = try TempStore()
        try await temp.store.recordText("keep this", limit: 50)
        let image = try await temp.store.recordImage(
            Data(repeating: 7, count: 2_048), width: 4, height: 4, format: "png", limit: 50
        )
        try await temp.store.createEntry(
            collectionID: LibraryCollection.Seed.prompts, title: "t", body: "a prompt"
        )

        let folder = try await temp.store.backUp()
        #expect(!folder.lastPathComponent.hasSuffix(BackupSchedule.partialSuffix))

        let restored = try LocalStore(locations: StorageLocations(root: folder), key: temp.key)
        let clips = try await restored.allClips()
        #expect(clips.count == 2)
        #expect(try await restored.allEntries().map(\.body) == ["a prompt"])
        #expect(try await restored.imageData(for: image!.id) == Data(repeating: 7, count: 2_048),
                "the sidecar came along, not just the row that points at it")
    }

    @Test("keeps the newest seven and reports the latest")
    func rotatesOnDisk() async throws {
        let temp = try TempStore()
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        for day in 0..<9 {
            try await temp.store.backUp(now: start.addingTimeInterval(Double(day) * 86_400))
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: temp.locations.backupsURL.path)
        #expect(names.count == BackupSchedule.keep)
        #expect(await temp.store.latestBackupDate() == start.addingTimeInterval(8 * 86_400))
    }

    @Test("a half-written snapshot from a crash is cleared, and folders we did not write stay")
    func cleansPartials() async throws {
        let temp = try TempStore()
        let backups = temp.locations.backupsURL
        let crashed = backups.appendingPathComponent("20200101T000000Z.partial")
        let manual = backups.appendingPathComponent("before-upgrade")
        try FileManager.default.createDirectory(at: crashed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: manual, withIntermediateDirectories: true)

        try await temp.store.backUp()

        #expect(!FileManager.default.fileExists(atPath: crashed.path))
        #expect(FileManager.default.fileExists(atPath: manual.path))
        #expect(await temp.store.latestBackupDate() != nil)
    }
}
