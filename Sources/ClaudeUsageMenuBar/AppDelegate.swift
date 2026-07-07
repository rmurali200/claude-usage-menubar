import Cocoa
import ServiceManagement

// Task { } bodies started here inherit this actor, so UI updates after an `await`
// (e.g. the network call in fetchUsage()) reliably resume on the main thread.
// Without this, mutating NSMenuItem.title from a background thread can crash
// AppKit's window-management code if it happens while the menu is open.
@MainActor
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchUsage()
            }
        }
        fetchUsage()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if lastFetch == nil || Date().timeIntervalSince(lastFetch!) > 60 {
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
            Logger.log("importFromClaudeCode failed: \(error)")
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
            // Record the attempt time on both success and failure. Otherwise a failed
            // fetch (e.g. a 429) never updates lastFetch, so the next dropdown open
            // looks "overdue" and immediately retries — hitting the same rate limit
            // again on every subsequent open instead of backing off.
            lastFetch = Date()
            do {
                let usage = try await UsageAPI.fetch()
                lastUsage = usage
                lastError = nil
                applyUsage(usage)
            } catch OAuthError.refreshTokenInvalid {
                // Likely Claude Code itself rotated the refresh token by refreshing
                // its own copy first — our copy is now permanently dead, not transient.
                Logger.log("refresh token invalidated (likely rotated by Claude Code) — disconnecting")
                OAuthClient.logout()
                refreshLoginState()
                statusInfoItem.title = "Reconnect needed — click Connect via Claude Code…"
            } catch {
                lastError = "\(error)"
                statusInfoItem.title = "Error fetching usage (see menu bar log)"
                Logger.log("fetchUsage failed: \(error)")
            }
        }
    }

    private func applyUsage(_ usage: UsageResponse) {
        statusInfoItem.title = "Claude Usage (5-hour · weekly)"

        var barText = ""
        if let five = usage.fiveHour {
            let pct = Int(five.utilization.rounded())
            barText = "\(pct)%"
            fiveHourItem.title = "5-hour: \(pct)% used" + Self.resetSuffix(five.resetsAt)
        } else {
            fiveHourItem.title = "5-hour: no data"
        }
        if let week = usage.sevenDay {
            let pct = Int(week.utilization.rounded())
            sevenDayItem.title = "Weekly: \(pct)% used" + Self.resetSuffix(week.resetsAt)
        } else {
            sevenDayItem.title = "Weekly: no data"
        }
        statusItem.button?.title = " " + barText
    }

    private static func resetSuffix(_ date: Date?) -> String {
        guard let date else { return "" }
        return " — resets \(relativeTime(date))"
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
