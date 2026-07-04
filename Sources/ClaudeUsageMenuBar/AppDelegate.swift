import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var lastFetch: Date?
    private var lastUsage: UsageResponse?
    private var lastError: String?

    private let fiveHourItem = NSMenuItem(title: "5-hour: —", action: nil, keyEquivalent: "")
    private let sevenDayItem = NSMenuItem(title: "Weekly: —", action: nil, keyEquivalent: "")
    private let statusInfoItem = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
    private let loginLogoutItem = NSMenuItem(title: "Connect via Claude Code…", action: #selector(loginOrLogoutTapped), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = MenuBarIcon.load()
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title = "⋯"

        let menu = NSMenu()
        menu.delegate = self
        loginLogoutItem.target = self
        launchAtLoginItem.target = self

        statusInfoItem.isEnabled = false
        fiveHourItem.isEnabled = false
        sevenDayItem.isEnabled = false

        menu.addItem(statusInfoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(fiveHourItem)
        menu.addItem(sevenDayItem)
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshTapped), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(loginLogoutItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        refreshLoginState()
        refreshLaunchAtLoginState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.fetchUsage()
        }
        fetchUsage()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 30 {
            fetchUsage()
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLoginState() {
        let loggedIn = OAuthClient.isLoggedIn
        loginLogoutItem.title = loggedIn ? "Disconnect" : "Connect via Claude Code…"
        if !loggedIn {
            statusItem.button?.title = "🔒"
            statusInfoItem.title = "Not connected"
            fiveHourItem.title = "5-hour: —"
            sevenDayItem.title = "Weekly: —"
        }
    }

    @objc private func loginOrLogoutTapped() {
        if OAuthClient.isLoggedIn {
            OAuthClient.logout()
            refreshLoginState()
            return
        }
        do {
            try OAuthClient.importFromClaudeCode()
            refreshLoginState()
            fetchUsage()
        } catch {
            statusInfoItem.title = "Couldn't find a Claude Code login on this Mac"
        }
    }

    @objc private func refreshTapped() {
        fetchUsage()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusInfoItem.title = "Couldn't change Launch at Login"
        }
        refreshLaunchAtLoginState()
    }

    @objc private func quitTapped() {
        NSApp.terminate(nil)
    }

    private func fetchUsage() {
        guard OAuthClient.isLoggedIn else {
            refreshLoginState()
            return
        }
        Task {
            do {
                let usage = try await UsageAPI.fetch()
                lastFetch = Date()
                lastUsage = usage
                lastError = nil
                applyUsage(usage)
            } catch {
                lastError = "\(error)"
                statusInfoItem.title = "Error fetching usage"
            }
        }
    }

    private func applyUsage(_ usage: UsageResponse) {
        statusInfoItem.title = "Claude Usage (5-hour · weekly)"

        var barText = ""
        if let five = usage.fiveHour {
            let pct = Int(five.utilization.rounded())
            barText = "\(pct)%"
            fiveHourItem.title = "5-hour: \(pct)% used — resets \(Self.relativeTime(five.resetsAt))"
        } else {
            fiveHourItem.title = "5-hour: no data"
        }
        if let week = usage.sevenDay {
            let pct = Int(week.utilization.rounded())
            sevenDayItem.title = "Weekly: \(pct)% used — resets \(Self.relativeTime(week.resetsAt))"
        } else {
            sevenDayItem.title = "Weekly: no data"
        }
        statusItem.button?.title = " " + barText
    }

    private static func relativeTime(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "soon" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "in \(days)d \(remHours)h"
        } else if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
}
