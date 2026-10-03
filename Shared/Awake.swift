import AppKit
import Foundation
import os

/// The `awake` script and its state. The extension is sandboxed, where
/// `NSHomeDirectory()` is its container, so paths start from the real home.
enum Awake {
    static let home: String = {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: dir)
    }()
    static let stateDir = home + "/.cache/awake"
    static let pidFile = stateDir + "/caffeinate.pid"
    static let requestFile = stateDir + "/request"
    static let script = home + "/.local/bin/awake"
    static let bundleID = "com.mohdkhan.awake"
    static let log = Logger(subsystem: bundleID, category: "toggle")

    /// The script keeps the pidfile exactly while caffeinate runs.
    static var isOn: Bool { FileManager.default.fileExists(atPath: pidFile) }

    static func set(_ on: Bool) async throws {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            try await requestFromAgent(on)
        } else {
            try await runScript(on)
        }
    }

    /// The sandboxed extension can't run the script. It writes a request the
    /// menu-bar app watches, launching that app in the background if needed.
    private static func requestFromAgent(_ on: Bool) async throws {
        log.notice("toggle \(on ? "on" : "off", privacy: .public) from the extension: asking the menu-bar app")
        try await launchAgentIfNeeded()
        try FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        try "\(on ? "on" : "off")\n".write(toFile: requestFile, atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now + .seconds(10)
        while isOn != on, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(80))
        }
        guard isOn == on else {
            throw on ? AwakeError.needsSudoersRule : AwakeError.failed("Awake didn't turn off. Click the cup in the menu bar, or run asleep.")
        }
    }

    private static func launchAgentIfNeeded() async throws {
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) { return }
        var appURL = Bundle.main.bundleURL
        for _ in 0..<3 { appURL.deleteLastPathComponent() } // …/Awake.app/Contents/PlugIns/AwakeControl.appex
        guard FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/Awake").path) else {
            throw AwakeError.notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await Task.sleep(for: .milliseconds(400))
    }

    /// `duration` (like "30m" or "2h") makes turning on timed; without it, on lasts until turned off.
    static func runScript(_ on: Bool, duration: String? = nil) async throws {
        log.notice("toggle \(on ? "on" : "off", privacy: .public) in Awake.app: running the script")
        guard FileManager.default.isExecutableFile(atPath: script) else { throw AwakeError.notInstalled }
        let (status, output) = try await run(on ? [duration].compactMap { $0 } : ["stop"])
        if on, !isOn {
            throw status == 0 || status == 3 || output.isEmpty ? AwakeError.needsSudoersRule : AwakeError.failed(output)
        }
        if !on, status != 0 {
            throw status == 3 ? AwakeError.needsSudoersRule : AwakeError.failed(output)
        }
    }

    private static func run(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        // A file, not a pipe: caffeinate and the watcher outlive the script.
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("awake-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: script)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["AWAKE_CALLER": "Control Center"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let lines = output.split(separator: "\n").map { $0.hasPrefix("awake: ") ? $0.dropFirst(7) : $0 }
        return (status, lines.joined(separator: "\n"))
    }
}

enum AwakeError: Error, CustomLocalizedStringResourceConvertible, LocalizedError {
    case notInstalled
    case needsSudoersRule
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notInstalled:
            "awake isn't installed at ~/.local/bin/awake. Run install.sh from the Awake project."
        case .needsSudoersRule:
            "Awake can't change lid sleep without a password. Install its sudoers rule once, in Terminal: \(Self.installCommand)"
        case .failed(let output):
            "\(output)"
        }
    }

    var errorDescription: String? { String(localized: localizedStringResource) }

    static var installCommand: String {
        let rule = Bundle.main.path(forResource: "awake", ofType: nil) ?? "sudoers.d/awake"
        return "sudo visudo -cf '\(rule)' && sudo install -m 0440 -o root -g wheel '\(rule)' /etc/sudoers.d/awake"
    }
}
