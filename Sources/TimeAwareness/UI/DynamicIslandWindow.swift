import Cocoa

/// A transparent, borderless NSPanel that floats above the menu bar.
class DynamicIslandWindow: NSPanel {
    
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Transparent & borderless
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        // Float above the menu bar but below system alerts
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        // Visible in screenshots (no sharingType restriction)
        
        // Start with mouse pass-through
        self.ignoresMouseEvents = true
        
        // Panel-specific
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    /// Prevent macOS from constraining the window below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}
