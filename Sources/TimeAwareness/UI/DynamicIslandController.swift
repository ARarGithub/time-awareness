import Cocoa
import SwiftUI

/// Manages the Dynamic Island window lifecycle, positioning, and hover/expand tracking.
class DynamicIslandController: ObservableObject {
    
    private var window: DynamicIslandWindow?
    private var hostingView: NSHostingView<DynamicIslandRootView>?
    private var trackingMonitor: Any?
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    /// Throttle mouse move callbacks to ~60fps
    private var lastMouseMoveTime: CFAbsoluteTime = 0
    private let mouseMoveThrottleInterval: CFAbsoluteTime = 1.0 / 60.0  // ~16ms
    
    // The view model shared with SwiftUI
    let viewModel = DynamicIslandViewModel()
    
    /// Compute window size from the largest pill size (settings state) + margin for flare/shadow
    private var windowWidth: CGFloat {
        let maxPill = max(viewModel.settingsSize.width, viewModel.expandedSize.width)
        return maxPill + 80  // extra space for flare + shadow
    }
    
    private var windowHeight: CGFloat {
        let maxPill = max(viewModel.settingsSize.height, viewModel.expandedSize.height)
        return maxPill + 60  // extra space for shadow
    }
    
    init() {
        setupWindow()
        setupMouseTracking()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigReload),
            name: .configDidReload,
            object: nil
        )
    }
    
    deinit {
        if let monitor = trackingMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMoveMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Window Setup
    
    private func setupWindow() {
        let w = windowWidth
        let h = windowHeight
        let frame = NSRect(x: 0, y: 0, width: w, height: h)
        
        window = DynamicIslandWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        let rootView = DynamicIslandRootView(viewModel: viewModel)
        
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        
        window.contentView = hosting
        hostingView = hosting
        
        positionWindow()
        window.orderFrontRegardless()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.positionWindow()
        }
    }
    
    /// Resize window and hosting view after config changes (barLength etc.)
    private func resizeWindow() {
        guard let window = window, let hosting = hostingView else { return }
        let w = windowWidth
        let h = windowHeight
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: w, height: h))
        let origin = window.frame.origin
        window.setFrame(NSRect(x: origin.x, y: origin.y, width: w, height: h), display: true)
        positionWindow()
    }
    
    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let w = windowWidth
        let h = windowHeight
        let x = screenFrame.midX - w / 2
        let y = screenFrame.maxY - h
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    @objc private func screenDidChange() {
        positionWindow()
    }
    
    @objc private func handleConfigReload() {
        viewModel.reloadConfig()
        resizeWindow()
    }
    
    // MARK: - Mouse Tracking
    
    private func setupMouseTracking() {
        // Global mouse move monitor (when our window doesn't have focus)
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove()
        }
        
        // Local mouse move monitor (when our window has focus)
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
        
        // Click monitor for expanding
        trackingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handleGlobalClick(event)
        }
    }
    
    private func handleMouseMove() {
        // Throttle: skip if called too soon after last invocation
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastMouseMoveTime >= mouseMoveThrottleInterval else { return }
        lastMouseMoveTime = now
        
        guard let window = window else { return }
        let mouseLocation = NSEvent.mouseLocation
        
        // Get the pill's current frame in screen coordinates
        let pillFrame = currentPillScreenFrame()
        let isInPill = pillFrame.contains(mouseLocation)
        
        switch viewModel.state {
        case .idle:
            if isInPill {
                window.ignoresMouseEvents = false
                viewModel.transitionTo(.hovered)
            }
        case .hovered:
            if !isInPill && !viewModel.isNotifying {
                window.ignoresMouseEvents = true
                viewModel.transitionTo(.idle)
            }
        case .expanded:
            // Use a larger hit area for expanded state
            let expandedFrame = currentExpandedScreenFrame()
            if !expandedFrame.contains(mouseLocation) {
                window.ignoresMouseEvents = true
                viewModel.transitionTo(.idle)
            }
        case .settings:
            let expandedFrame = currentExpandedScreenFrame()
            if !expandedFrame.contains(mouseLocation) {
                // Don't auto-collapse from settings - user needs to interact
            }
        }
    }
    
    private func handleGlobalClick(_ event: NSEvent) {
        guard let window = window else { return }
        let mouseLocation = NSEvent.mouseLocation
        
        switch viewModel.state {
        case .hovered:
            let pillFrame = currentPillScreenFrame()
            if pillFrame.contains(mouseLocation) {
                window.ignoresMouseEvents = false
                viewModel.transitionTo(.expanded)
            }
        case .expanded:
            let expandedFrame = currentExpandedScreenFrame()
            if !expandedFrame.contains(mouseLocation) {
                window.ignoresMouseEvents = true
                viewModel.transitionTo(.idle)
            }
        case .settings:
            let expandedFrame = currentExpandedScreenFrame()
            if !expandedFrame.contains(mouseLocation) {
                window.ignoresMouseEvents = true
                viewModel.transitionTo(.idle)
            }
        default:
            break
        }
    }
    
    // MARK: - Hit Area Calculations
    
    /// Returns the screen-space rect of the idle/hovered pill (including flare)
    private func currentPillScreenFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let pillSize = viewModel.currentPillSize
        let flare: CGFloat = 16  // account for the top flare extending beyond pill width
        let x = screenFrame.midX - pillSize.width / 2 - flare
        let y = screenFrame.maxY - pillSize.height - 4
        
        let padding: CGFloat = 8
        return NSRect(
            x: x - padding,
            y: y - padding,
            width: pillSize.width + flare * 2 + padding * 2,
            height: pillSize.height + padding * 2
        )
    }
    
    /// Returns the screen-space rect of the expanded/settings island
    private func currentExpandedScreenFrame() -> NSRect {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.frame
        
        let size: CGSize
        switch viewModel.state {
        case .settings:
            size = viewModel.settingsSize
        default:
            size = viewModel.expandedSize
        }
        let flare: CGFloat = 20
        let x = screenFrame.midX - size.width / 2 - flare
        let y = screenFrame.maxY - size.height - 4
        
        let padding: CGFloat = 16
        return NSRect(
            x: x - padding,
            y: y - padding,
            width: size.width + flare * 2 + padding * 2,
            height: size.height + padding * 2
        )
    }
}
