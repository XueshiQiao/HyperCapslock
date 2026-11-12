import Foundation
import CryptoKit

/// Identifies which HyperCapslock configuration file a backup belongs to.
enum ConfigFileKind: String, Codable, CaseIterable, Equatable {
  case mappings = "mappings"
  case appConfig = "app-config"

  /// Filename prefix used in `<dataDir>/backups/<prefix>-<yyyyMMdd-HHmmss>-<uuid>.yml`.
  var backupPrefix: String {
    switch self {
    case .mappings: return "action_mappings"
    case .appConfig: return "app_config"
    }
  }

  /// Active filename inside `<dataDir>/`.
  var activeFileName: String {
    switch self {
    case .mappings: return "action_mappings.yml"
    case .appConfig: return "app_config.yml"
    }
  }

  static func parseCLI(_ raw: String) -> ConfigFileKind? {
    switch raw.lowercased() {
    case "mappings", "action_mappings", "action-mappings":
      return .mappings
    case "app-config", "app_config", "appconfig":
      return .appConfig
    default:
      return nil
    }
  }

  static func infer(fromFileName fileName: String) -> ConfigFileKind? {
    let lower = fileName.lowercased()
    if lower.hasPrefix("action_mappings-") || lower == "action_mappings.yml" {
      return .mappings
    }
    if lower.hasPrefix("app_config-") || lower == "app_config.yml" {
      return .appConfig
    }
    return nil
  }
}

/// Metadata for a single `.yml` backup file in `<dataDir>/backups/`.
struct ConfigBackupEntry: Codable, Equatable {
  let fileName: String
  let path: String
  let kind: ConfigFileKind
  let timestamp: String?
  let uuid: String?
  let sizeBytes: Int
  let createdAtEpochMs: Int64
}

enum ConfigBackupError: LocalizedError {
  case missingTarget
  case backupNotFound(String)
  case noBackupsAvailable(ConfigFileKind?)
  case ambiguousBackupKind(String)
  case io(String)

  var errorDescription: String? {
    switch self {
    case .missingTarget:
      return "Specify either --latest or --file <filename-or-path>"
    case .backupNotFound(let spec):
      return "Backup file not found: \(spec)"
    case .noBackupsAvailable(let kind):
      if let kind {
        return "No backups found for \(kind.rawValue)"
      }
      return "No backups found in backups directory"
    case .ambiguousBackupKind(let name):
      return "Cannot infer config kind from '\(name)'; pass --kind mappings or --kind app-config"
    case .io(let msg):
      return msg
    }
  }
}

/// Manages immutable, UUID-versioned YAML configuration backups under `<dataDir>/backups/`.
///
/// Filename format: `<prefix>-<yyyyMMdd-HHmmss>-<uuid>.yml` where `<prefix>` is
/// `action_mappings` or `app_config`, timestamp is local `yyyyMMdd-HHmmss` (`en_US_POSIX`),
/// and `<uuid>` is `UUID().uuidString.lowercased()`.
///
/// Historical backups are NEVER automatically deleted.
struct ConfigBackupManager {
  let dataDirectory: URL

  init(dataDirectory: URL) {
    self.dataDirectory = dataDirectory.standardizedFileURL
  }

  var backupsDirectory: URL {
    dataDirectory.appendingPathComponent("backups", isDirectory: true)
  }

  func activeFileURL(for kind: ConfigFileKind) -> URL {
    dataDirectory.appendingPathComponent(kind.activeFileName, isDirectory: false)
  }

  // MARK: - Hashing & Naming

  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func timestampFormatter() -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = .autoupdatingCurrent
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
  }

  static func formatTimestamp(_ date: Date) -> String {
    timestampFormatter().string(from: date)
  }

  static func makeBackupFileName(
    kind: ConfigFileKind,
    date: Date = Date(),
    uuid: UUID = UUID()
  ) -> String {
    "\(kind.backupPrefix)-\(formatTimestamp(date))-\(uuid.uuidString.lowercased()).yml"
  }

  /// Parses `<prefix>-<yyyyMMdd-HHmmss>-<uuid>.yml`. Returns `(kind, timestamp, uuid)` if matched.
  static func parseUUIDBackupFileName(_ fileName: String) -> (kind: ConfigFileKind, timestamp: String, date: Date?, uuid: String)? {
    guard fileName.lowercased().hasSuffix(".yml") else { return nil }
    let stem = String(fileName.dropLast(4))
    for kind in ConfigFileKind.allCases {
      let prefix = kind.backupPrefix + "-"
      guard stem.hasPrefix(prefix) else { continue }
      let rest = String(stem.dropFirst(prefix.count))
      // Expect "yyyyMMdd-HHmmss-<36-char-uuid>" (15 + 1 + 36 = 52 chars)
      guard rest.count == 52 else { continue }
      let tsEnd = rest.index(rest.startIndex, offsetBy: 15)
      let sepIdx = tsEnd
      guard rest[sepIdx] == "-" else { continue }
      let ts = String(rest[..<tsEnd])
      let uuidPart = String(rest[rest.index(after: sepIdx)...])
      guard UUID(uuidString: uuidPart) != nil,
            let parsedDate = timestampFormatter().date(from: ts) else {
        continue
      }
      return (kind, ts, parsedDate, uuidPart.lowercased())
    }
    return nil
  }

  // MARK: - Backup Creation

  /// Write `data` to `<dataDir>/backups/<prefix>-<yyyyMMdd-HHmmss>-<uuid>.yml`.
  @discardableResult
  func createBackup(
    data: Data,
    kind: ConfigFileKind,
    date: Date = Date(),
    uuid: UUID = UUID()
  ) throws -> URL {
    let dir = backupsDirectory
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let fileName = Self.makeBackupFileName(kind: kind, date: date, uuid: uuid)
      let dst = dir.appendingPathComponent(fileName, isDirectory: false)
      try data.write(to: dst, options: .atomic)
      return dst
    } catch {
      throw ConfigBackupError.io("Failed to write backup for \(kind.activeFileName): \(error.localizedDescription)")
    }
  }

  /// If the active config file exists on disk, is non-empty, and its bytes differ from
  /// `incomingData`, back up the active file first and return `(backupURL, backedUpSHA256)`.
  func backupActiveFileIfChanged(
    kind: ConfigFileKind,
    incomingData: Data
  ) throws -> (backupURL: URL, sha256: String)? {
    let activeURL = activeFileURL(for: kind)
    guard FileManager.default.fileExists(atPath: activeURL.path) else { return nil }
    let existingData: Data
    do {
      existingData = try Data(contentsOf: activeURL)
    } catch {
      throw ConfigBackupError.io("Failed to read existing \(kind.activeFileName): \(error.localizedDescription)")
    }
    guard !existingData.isEmpty, existingData != incomingData else { return nil }
    let url = try createBackup(data: existingData, kind: kind)
    return (url, Self.sha256Hex(existingData))
  }

  // MARK: - Listing & Resolution

  /// Lists all `.yml` backups in `<dataDir>/backups/` sorted newest-first.
  func listBackups(kind filterKind: ConfigFileKind? = nil) -> [ConfigBackupEntry] {
    let dir = backupsDirectory
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: dir,
      includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    struct SortableEntry {
      let entry: ConfigBackupEntry
      let secondBucket: Int64
      let preciseMtime: TimeInterval
    }

    var items: [SortableEntry] = []
    for url in urls where url.pathExtension.lowercased() == "yml" {
      let fileName = url.lastPathComponent
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == false { continue }

      let mtime = values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
      let size = values?.fileSize ?? 0

      if let parsed = Self.parseUUIDBackupFileName(fileName) {
        if let filterKind, parsed.kind != filterKind { continue }
        let sec = Int64((parsed.date ?? mtime).timeIntervalSince1970)
        let epochMs = Int64(mtime.timeIntervalSince1970 * 1000.0)
        let entry = ConfigBackupEntry(
          fileName: fileName,
          path: url.standardizedFileURL.path,
          kind: parsed.kind,
          timestamp: parsed.timestamp,
          uuid: parsed.uuid,
          sizeBytes: size,
          createdAtEpochMs: epochMs
        )
        items.append(SortableEntry(entry: entry, secondBucket: sec, preciseMtime: mtime.timeIntervalSince1970))
      } else if let inferred = ConfigFileKind.infer(fromFileName: fileName) {
        if let filterKind, inferred != filterKind { continue }
        let sec = Int64(mtime.timeIntervalSince1970)
        let epochMs = Int64(mtime.timeIntervalSince1970 * 1000.0)
        let entry = ConfigBackupEntry(
          fileName: fileName,
          path: url.standardizedFileURL.path,
          kind: inferred,
          timestamp: Self.formatTimestamp(mtime),
          uuid: nil,
          sizeBytes: size,
          createdAtEpochMs: epochMs
        )
        items.append(SortableEntry(entry: entry, secondBucket: sec, preciseMtime: mtime.timeIntervalSince1970))
      }
    }

    items.sort { a, b in
      if a.secondBucket != b.secondBucket { return a.secondBucket > b.secondBucket }
      if a.preciseMtime != b.preciseMtime { return a.preciseMtime > b.preciseMtime }
      return a.entry.fileName > b.entry.fileName
    }
    return items.map(\.entry)
  }

  /// Resolves a rollback target from `--latest` or `--file <filename-or-path>`.
  func resolveBackup(
    latest: Bool,
    fileSpec: String?,
    kind: ConfigFileKind?
  ) throws -> (url: URL, kind: ConfigFileKind) {
    if let rawSpec = fileSpec?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSpec.isEmpty {
      let expanded = NSString(string: rawSpec).expandingTildeInPath
      let directURL = URL(fileURLWithPath: expanded).standardizedFileURL
      let inBackupsURL = backupsDirectory.appendingPathComponent(rawSpec, isDirectory: false).standardizedFileURL
      let resolvedURL: URL
      if FileManager.default.fileExists(atPath: directURL.path) {
        resolvedURL = directURL
      } else if FileManager.default.fileExists(atPath: inBackupsURL.path) {
        resolvedURL = inBackupsURL
      } else {
        throw ConfigBackupError.backupNotFound(rawSpec)
      }
      let resolvedKind = kind ?? ConfigFileKind.infer(fromFileName: resolvedURL.lastPathComponent)
      guard let finalKind = resolvedKind else {
        throw ConfigBackupError.ambiguousBackupKind(resolvedURL.lastPathComponent)
      }
      return (resolvedURL, finalKind)
    }

    guard latest else {
      throw ConfigBackupError.missingTarget
    }
    let backups = listBackups(kind: kind)
    guard let newest = backups.first else {
      throw ConfigBackupError.noBackupsAvailable(kind)
    }
    return (URL(fileURLWithPath: newest.path), newest.kind)
  }
}
