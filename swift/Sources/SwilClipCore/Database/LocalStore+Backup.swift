import Foundation

/// When to back up, what to call it, and which snapshots to let go.
///
/// Pure, so every rule is a unit test. The store does the I/O; this decides.
///
/// ## Why the app backs itself up
///
/// The data directory had grown five hand-made `SwilClipSwift.backup-*`
/// siblings — the need was real, the tool was `cp -R`. And `cp -R` on a live
/// SQLite database is not a backup: with WAL on, the newest writes live in the
/// `-wal` file, and copying the three files at slightly different moments can
/// capture a database that never existed. `VACUUM INTO` produces one
/// consistent, self-contained file from inside the connection.
public enum BackupSchedule {
    /// Snapshots kept. A week of dailies: enough to reach back past a bad day,
    /// small enough not to matter (each is the size of the database).
    public static let keep = 7
    /// Minimum age of the newest snapshot before launch takes another.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Suffix of a snapshot still being written. Renamed away on success, so a
    /// crash mid-backup can never leave something that *looks* restorable.
    public static let partialSuffix = ".partial"

    /// `20261101T125000Z` — UTC, so names sort in time order as plain strings
    /// and do not jump when the Mac changes time zone.
    public static func folderName(for date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(fromFolderName name: String) -> Date? {
        formatter.date(from: name)
    }

    public static func isDue(latest: Date?, now: Date) -> Bool {
        guard let latest else { return true }
        return now.timeIntervalSince(latest) >= interval
    }

    /// The snapshots to delete, given every name in the backups folder.
    ///
    /// **Only names this type wrote are candidates.** A folder the user put
    /// there by hand — a copy taken before an upgrade, say — is not ours to
    /// rotate away.
    public static func expired(_ names: [String], keep: Int = keep) -> [String] {
        let ours = names.filter { date(fromFolderName: $0) != nil }.sorted(by: >)
        return Array(ours.dropFirst(max(keep, 0)))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }()
}

extension StorageLocations {
    public var backupsURL: URL { root.appendingPathComponent("Backups", isDirectory: true) }
}

extension LocalStore {
    /// Write a snapshot of the database and its image sidecars, then rotate.
    ///
    /// Runs on the store's actor, so no capture can land between the database
    /// snapshot and the sidecar copy. The snapshot is encrypted exactly as the
    /// live data is — rows and sidecars are sealed with the Keychain key — so a
    /// backup is only readable on a Mac that holds that key.
    ///
    /// - Returns: the finished snapshot's folder.
    @discardableResult
    public func backUp(now: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        let backups = locations.backupsURL
        try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
        try removePartialBackups(in: backups)

        let name = BackupSchedule.folderName(for: now)
        let final = backups.appendingPathComponent(name, isDirectory: true)
        let partial = backups.appendingPathComponent(
            name + BackupSchedule.partialSuffix, isDirectory: true
        )
        try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            let snapshot = StorageLocations(root: partial)
            try database.execute("VACUUM INTO ?", [.text(snapshot.databaseURL.path)])
            if fileManager.fileExists(atPath: locations.blobsURL.path) {
                try fileManager.copyItem(at: locations.blobsURL, to: snapshot.blobsURL)
            }
            // Two backups in the same second would collide; the newer wins.
            if fileManager.fileExists(atPath: final.path) {
                try fileManager.removeItem(at: final)
            }
            try fileManager.moveItem(at: partial, to: final)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }

        let names = try fileManager.contentsOfDirectory(atPath: backups.path)
        for expired in BackupSchedule.expired(names) {
            try? fileManager.removeItem(at: backups.appendingPathComponent(expired))
        }
        return final
    }

    /// The newest finished snapshot, if any.
    public func latestBackupDate() -> Date? {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: locations.backupsURL.path
        )) ?? []
        return names.compactMap(BackupSchedule.date(fromFolderName:)).max()
    }

    /// Leftovers from a backup that crashed or was killed half-way.
    private func removePartialBackups(in backups: URL) throws {
        for name in try FileManager.default.contentsOfDirectory(atPath: backups.path)
        where name.hasSuffix(BackupSchedule.partialSuffix) {
            try? FileManager.default.removeItem(at: backups.appendingPathComponent(name))
        }
    }
}
