import AppKit
import ServiceManagement
import WidgetKit

// `Awake --reload`: the awake script runs this after every change so the toggle matches.
if CommandLine.arguments.dropFirst().first == "--reload" {
    ControlCenter.shared.reloadAllControls()
    DistributedNotificationCenter.default().post(name: Agent.refreshNotification, object: nil)
    Task { @MainActor in
        _ = try? await ControlCenter.shared.currentControls()
        exit(0)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    dispatchMain()
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let agent = Agent()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        agent.start()
        // Once: after that, "Open at Login" in the menu is the user's choice.
        if !UserDefaults.standard.bool(forKey: "registeredLoginItem") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "registeredLoginItem")
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !Agent.presentingAlert { NSApp.hide(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    private func installMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}
