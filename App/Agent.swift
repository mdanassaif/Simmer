import AppKit
import ServiceManagement
import WidgetKit

@MainActor
final class Agent {
    static let refreshNotification = Notification.Name("com.mohdkhan.awake.refresh")
    /// While an alert is up the app must stay frontmost (see applicationDidBecomeActive).
    static var presentingAlert = false

    private let status = StatusItemController()
    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private var handlingRequest = false

    func start() {
        try? FileManager.default.createDirectory(atPath: Awake.stateDir, withIntermediateDirectories: true)
        status.install(agent: self)
        watchStateDirectory()
        DistributedNotificationCenter.default().addObserver(forName: Self.refreshNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.status.refresh() }
        }
        Task { await consumeRequest() }
        ControlCenter.shared.reloadAllControls()
        Awake.log.notice("menu-bar agent ready")
    }

    /// Turns awake on (optionally for a duration like "30m") or off, and explains any failure.
    func set(_ on: Bool, duration: String? = nil) async {
        do {
            try await Awake.runScript(on, duration: duration)
        } catch {
            Awake.log.error("menu-bar switch failed: \(error.localizedDescription, privacy: .public)")
            present(error)
        }
        refreshAll()
    }

    private func consumeRequest() async {
        guard !handlingRequest else { return }
        guard let body = try? String(contentsOfFile: Awake.requestFile, encoding: .utf8) else {
            status.refresh()
            return
        }
        try? FileManager.default.removeItem(atPath: Awake.requestFile)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == "on" || trimmed == "off" else { return }
        handlingRequest = true
        defer { handlingRequest = false }
        do {
            try await Awake.runScript(trimmed == "on")
        } catch {
            Awake.log.error("request \(trimmed, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshAll()
    }

    private func refreshAll() {
        status.refresh()
        ControlCenter.shared.reloadAllControls()
    }

    private func present(_ error: Error) {
        let alert = NSAlert()
        var command: String?
        if case AwakeError.needsSudoersRule = error {
            let install = AwakeError.installCommand
            command = install
            alert.messageText = "Awake needs a one-time setup"
            alert.informativeText = """
                To keep the Mac awake with the lid closed, Awake changes a system sleep setting, \
                which normally needs your password. Paste this command into Terminal once and it \
                will never have to ask:

                \(install)
                """
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.alertStyle = .warning
            alert.messageText = "Awake couldn't switch"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
        }
        if runModal(alert) == .alertFirstButtonReturn, let command {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    func showHelp() {
        let alert = NSAlert()
        alert.messageText = "How to use Awake"
        alert.informativeText = """
            Awake keeps this Mac running — even with the lid closed — so downloads, builds and \
            remote sessions don't get cut off.

            Turn it on or off
            • Click the cup in the menu bar, or
            • use the Awake tile in Control Center (Edit Controls > Awake), or
            • in Terminal: awake, awake 45m, awake -- some-command, and asleep to stop.

            The cup is orange and steaming while Awake is on.

            It turns itself off
            • when a timer you chose runs out,
            • on battery at 10% or less (20% with the lid closed),
            • if the Mac gets hot with the lid closed.
            You get a notification each time, and normal sleep comes back.

            Don't put a closed, awake Mac in a bag: it can overheat.
            """
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        Self.presentingAlert = true
        defer { Self.presentingAlert = false }
        NSApp.activate()
        return alert.runModal()
    }

    private func watchStateDirectory() {
        directoryFD = open(Awake.stateDir, O_EVTONLY)
        guard directoryFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                await self?.consumeRequest()
                self?.status.refresh()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryFD, fd >= 0 { close(fd) }
        }
        source.resume()
        directorySource = source
    }
}

/// What the script recorded about the running session (~/.cache/awake/session).
struct Session {
    let mode: String
    let until: Date?

    static var current: Session? {
        guard Awake.isOn,
              let body = try? String(contentsOfFile: Awake.stateDir + "/session", encoding: .utf8) else { return nil }
        let parts = body.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return nil }
        let until = Double(parts[1]).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return Session(mode: String(parts[0]), until: until)
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private static let durations: [(title: String, argument: String)] = [
        ("15 Minutes", "15m"), ("30 Minutes", "30m"), ("1 Hour", "1h"),
        ("2 Hours", "2h"), ("4 Hours", "4h"), ("8 Hours", "8h"),
    ]

    private var item: NSStatusItem?
    private weak var agent: Agent?
    private var steam: Timer?
    private var frame = 0

    func install(agent: Agent) {
        self.agent = agent
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = [.removalAllowed]
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        refresh()
    }

    func refresh() {
        let on = Awake.isOn
        item?.button?.appearsDisabled = false
        item?.button?.toolTip = on ? "Awake is on — the Mac won't sleep" : "Awake is off — the Mac sleeps normally"
        if on {
            startSteam()
        } else {
            steam?.invalidate()
            steam = nil
            item?.button?.image = CupIcon.off()
        }
    }

    /// Animates the steam while awake is on.
    private func startSteam() {
        guard steam == nil else { return }
        item?.button?.image = CupIcon.on(frame: frame)
        let timer = Timer(timeInterval: 1.0 / 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frame = (self.frame + 1) % CupIcon.frameCount
                self.item?.button?.image = CupIcon.on(frame: self.frame)
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        steam = timer
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let on = Awake.isOn
        menu.removeAllItems()
        menu.addItem(info(statusLine(on: on)))
        menu.addItem(info(on ? "The Mac stays awake, even with the lid closed." : "The Mac sleeps normally."))
        menu.addItem(.separator())

        if on {
            menu.addItem(action("Turn Off", #selector(turnOff)))
        } else {
            menu.addItem(action("Keep Awake", #selector(turnOn)))
        }
        let timed = NSMenuItem(title: on ? "Switch to a Timer" : "Keep Awake For", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for duration in Self.durations {
            let entry = action(duration.title, #selector(turnOnTimed(_:)))
            entry.representedObject = duration.argument
            submenu.addItem(entry)
        }
        timed.submenu = submenu
        menu.addItem(timed)
        menu.addItem(.separator())

        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(action("How to Use Awake…", #selector(help)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func statusLine(on: Bool) -> String {
        guard on else { return "Awake is off" }
        guard let session = Session.current else { return "Awake is on" }
        switch session.mode {
        case "timed":
            guard let until = session.until else { return "Awake is on" }
            let left = until.timeIntervalSinceNow
            let time = until.formatted(date: .omitted, time: .shortened)
            if left < 60 { return "Awake is on — less than a minute left" }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .abbreviated
            return "Awake is on — \(formatter.string(from: left) ?? "") left (until \(time))"
        case "command":
            return "Awake is on while a command runs"
        default:
            return "Awake is on until you turn it off"
        }
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func turnOn() {
        Task { await agent?.set(true) }
    }

    @objc private func turnOnTimed(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? String else { return }
        Task { await agent?.set(true, duration: duration) }
    }

    @objc private func turnOff() {
        Task { await agent?.set(false) }
    }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }

    @objc private func help() {
        agent?.showHelp()
    }
}
