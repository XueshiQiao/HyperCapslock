import Foundation
import Darwin

/// Out-of-process guard for the CapsLock→F18 hidutil remap (#28).
///
/// The remap is system state that outlives us. A normal quit (and, since
/// SIGTERM/SIGINT/SIGHUP are routed to `terminate:`, a `kill`) removes it in
/// `applicationWillTerminate` — but a crash or SIGKILL (Force Quit) can't run
/// any of our code, and leaves a CapsLock key that does nothing until we're
/// relaunched or the Mac reboots. With Caps Lock on, that locks the user out
/// at the next password prompt.
///
/// So every app instance re-executes its own binary as a watchdog that waits
/// for the app to exit, then removes the remap — unless another instance is
/// still alive. "Alive" is decided by an `flock` on a shared lock file:
/// - each app instance holds it SHARED from before it installs the remap until
///   it exits (the kernel drops it on death, SIGKILL included);
/// - the watchdog takes it EXCLUSIVE, non-blocking, and only cleans up if that
///   succeeds — holding it while cleaning, so an instance starting at that
///   moment waits for the cleanup before installing its own remap.
/// Dev and Release share the file because they share the same global hidutil
/// state, so it lives in the Release data dir even for Dev. Not in /tmp: a file
/// deleted there while instances run (cleaner apps) would split the instances
/// onto different inodes that can't see each other's locks.
enum CapsLockWatchdog {
  static let argument = "--capslock-watchdog"
  private static let lockDir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("me.xueshi.hypercapslock", isDirectory: true)
  }()
  private static let lockPath = lockDir.appendingPathComponent("remap.lock").path
  /// Kept open for the process lifetime; closing it would drop the lock.
  private static var instanceLockFD: Int32 = -1

  private static func openLockFile() -> Int32 {
    try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
    return open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
  }

  // MARK: App side

  /// Call before the first remap install. Blocks only while a watchdog is
  /// mid-cleanup, i.e. for the duration of one `hidutil` call.
  static func holdInstanceLock() {
    guard instanceLockFD < 0 else { return }
    let fd = openLockFile()
    guard fd >= 0 else {
      FileLog.shared.warn("CapsLockWatchdog: can't open \(lockPath) (errno \(errno)) — a watchdog may strip this instance's remap.")
      return
    }
    if flock(fd, LOCK_SH) != 0 {
      FileLog.shared.warn("CapsLockWatchdog: flock(LOCK_SH) failed (errno \(errno)).")
    }
    instanceLockFD = fd
  }

  /// Launch the watchdog for this process. Best effort: on failure we're just
  /// back to the in-process cleanup.
  static func spawn() {
    guard let exe = Bundle.main.executableURL else { return }
    let p = Process()
    p.executableURL = exe
    p.arguments = [argument, String(getpid())]
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
      try p.run()
      FileLog.shared.info("CapsLockWatchdog: spawned pid=\(p.processIdentifier) for app pid=\(getpid()).")
    } catch {
      FileLog.shared.warn("CapsLockWatchdog: spawn failed: \(error.localizedDescription)")
    }
  }

  // MARK: Watchdog side

  /// Entry point when launched with `--capslock-watchdog <pid>` (see main.swift).
  /// Never creates an NSApplication, so no Dock icon / menu bar item.
  static func run(watching parent: pid_t) -> Never {
    // Own session: a terminal Ctrl-C / hangup aimed at the app's process
    // group must not take the watchdog down with it.
    _ = setsid()
    signal(SIGHUP, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
    source.setEventHandler {
      cleanUpIfNoInstanceAlive(parent)
      exit(0)
    }
    source.resume()
    // The parent may already be gone before the source was armed.
    if kill(parent, 0) != 0 && errno == ESRCH {
      cleanUpIfNoInstanceAlive(parent)
      exit(0)
    }
    dispatchMain()
  }

  private static func cleanUpIfNoInstanceAlive(_ parent: pid_t) {
    let fd = openLockFile()
    guard fd >= 0 else { return }
    defer { close(fd) }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      FileLog.shared.info("CapsLockWatchdog: app pid=\(parent) exited; another HyperCapslock instance is alive — leaving the remap to it.")
      return
    }
    FileLog.shared.info("CapsLockWatchdog: app pid=\(parent) exited and no instance is alive — removing the CapsLock remap.")
    HidUtil.cleanupRemap()
    _ = flock(fd, LOCK_UN)
  }
}
