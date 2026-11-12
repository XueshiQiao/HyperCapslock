import Foundation

/// Cross-process IPC over `DistributedNotificationCenter` between `HyperCapslock cli`
/// and the running HyperCapslock GUI instance owning the same `dataDirectory`.
///
/// Every message carries `targetDataDir` normalized via `canonicalPath(_:)`, so
/// Release (`me.xueshi.hypercapslock`), Dev (`me.xueshi.hypercapslock.debug`),
/// UI-test temp dirs, and custom `--data-dir` instances never cross-talk.
enum ReloadIPC {
  enum Wire {
    static let ping = Notification.Name("me.xueshi.hypercapslock.ipc.ping")
    static let pong = Notification.Name("me.xueshi.hypercapslock.ipc.pong")
    static let reloadConfig = Notification.Name("me.xueshi.hypercapslock.ipc.reloadConfig")
    static let reloadConfigAck = Notification.Name("me.xueshi.hypercapslock.ipc.reloadConfigAck")
  }

  struct PingRequest: Codable, Equatable {
    let requestId: String
    let targetDataDir: String
  }

  struct PongResponse: Codable, Equatable {
    let requestId: String
    let targetDataDir: String
    let pid: Int32
    let appVersion: String
    let bundleIdentifier: String
    let status: String
    let mappingsCount: Int
    let customActionsCount: Int
  }

  struct ReloadRequest: Codable, Equatable {
    let requestId: String
    let targetDataDir: String
    let backedUpMappingsSHA256: String?
    let backedUpAppConfigSHA256: String?
  }

  struct ReloadAck: Codable, Equatable {
    let requestId: String
    let targetDataDir: String
    let ok: Bool
    let pid: Int32
    let mappingsCount: Int
    let customActionsCount: Int
    let backupFilesCreated: [String]
    let errors: [String]
    let warnings: [String]
  }

  // MARK: - Path Normalization

  /// Resolves symlinks (e.g. `/tmp` → `/private/tmp`) and standardizes `url` so
  /// sender and receiver always compare identical canonical directory strings.
  static func canonicalPath(_ url: URL) -> String {
    let std = url.standardizedFileURL
    if FileManager.default.fileExists(atPath: std.path) {
      return std.resolvingSymlinksInPath().standardizedFileURL.path
    }
    let parent = std.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    return parent.appendingPathComponent(std.lastPathComponent, isDirectory: true).standardizedFileURL.path
  }

  // MARK: - Wire Encoding / Decoding

  static func makeUserInfo<T: Encodable>(_ payload: T, requestId: String, targetDataDir: String) -> [String: Any]? {
    guard let data = try? JSONEncoder().encode(payload),
          let json = String(data: data, encoding: .utf8) else {
      return nil
    }
    return [
      "requestId": requestId,
      "targetDataDir": targetDataDir,
      "payload": json,
    ]
  }

  static func decodePayload<T: Decodable>(_ type: T.Type, from notification: Notification) -> T? {
    guard let json = notification.userInfo?["payload"] as? String,
          let data = json.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(type, from: data)
  }

  static func post(_ name: Notification.Name, userInfo: [String: Any]) {
    DistributedNotificationCenter.default().postNotificationName(
      name,
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
  }

  // MARK: - CLI Synchronous Client Helpers

  /// Pings any running HyperCapslock instance owning `dataDirectory`.
  static func ping(dataDirectory: URL, timeout: TimeInterval = 0.35) -> PongResponse? {
    let targetDir = canonicalPath(dataDirectory)
    let reqID = UUID().uuidString.lowercased()
    let req = PingRequest(requestId: reqID, targetDataDir: targetDir)
    guard let info = makeUserInfo(req, requestId: reqID, targetDataDir: targetDir) else { return nil }

    let dnc = DistributedNotificationCenter.default()
    var received: PongResponse?
    let observer = dnc.addObserver(
      forName: Wire.pong,
      object: nil,
      queue: nil
    ) { note in
      guard (note.userInfo?["requestId"] as? String) == reqID,
            (note.userInfo?["targetDataDir"] as? String) == targetDir,
            let pong = decodePayload(PongResponse.self, from: note) else {
        return
      }
      received = pong
    }
    defer { dnc.removeObserver(observer) }

    post(Wire.ping, userInfo: info)

    let deadline = Date().addingTimeInterval(timeout)
    while received == nil && Date() < deadline {
      let step = min(deadline, Date().addingTimeInterval(0.03))
      _ = RunLoop.current.run(mode: .default, before: step)
    }
    return received
  }

  /// Sends `reloadConfig` to the running HyperCapslock instance owning `dataDirectory`
  /// and waits up to `timeout` (default 2.0s) for `reloadConfigAck`.
  static func requestReload(
    dataDirectory: URL,
    backedUpMappingsSHA256: String? = nil,
    backedUpAppConfigSHA256: String? = nil,
    timeout: TimeInterval = 2.0
  ) -> ReloadAck? {
    let targetDir = canonicalPath(dataDirectory)
    let reqID = UUID().uuidString.lowercased()
    let req = ReloadRequest(
      requestId: reqID,
      targetDataDir: targetDir,
      backedUpMappingsSHA256: backedUpMappingsSHA256,
      backedUpAppConfigSHA256: backedUpAppConfigSHA256
    )
    guard let info = makeUserInfo(req, requestId: reqID, targetDataDir: targetDir) else { return nil }

    let dnc = DistributedNotificationCenter.default()
    var received: ReloadAck?
    let observer = dnc.addObserver(
      forName: Wire.reloadConfigAck,
      object: nil,
      queue: nil
    ) { note in
      guard (note.userInfo?["requestId"] as? String) == reqID,
            (note.userInfo?["targetDataDir"] as? String) == targetDir,
            let ack = decodePayload(ReloadAck.self, from: note) else {
        return
      }
      received = ack
    }
    defer { dnc.removeObserver(observer) }

    post(Wire.reloadConfig, userInfo: info)

    let deadline = Date().addingTimeInterval(timeout)
    while received == nil && Date() < deadline {
      let step = min(deadline, Date().addingTimeInterval(0.04))
      _ = RunLoop.current.run(mode: .default, before: step)
    }
    return received
  }
}
