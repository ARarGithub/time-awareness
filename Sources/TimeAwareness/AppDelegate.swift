import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var islandController: DynamicIslandController?
    private var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we're an agent app (no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        requestNotificationAuthorization()
        
        // Initialize config (creates default if needed)
        ConfigManager.shared.ensureDefaultConfig()
        ConfigManager.shared.load()
        
        // Create the Dynamic Island
        islandController = DynamicIslandController()
        
        // Create menu bar status item
        setupStatusItem()
    }

    private func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // MARK: - Menu Bar Status Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "clock.circle.fill", accessibilityDescription: "Time Awareness")
            button.image?.size = NSSize(width: 18, height: 18)
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reloadItem.target = self
        reloadItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(reloadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Time Awareness", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func openSettings() {
        islandController?.viewModel.transitionTo(.settings)
    }
    
    @objc private func reloadConfig() {
        ConfigManager.shared.load()
        islandController?.viewModel.reloadConfig()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
