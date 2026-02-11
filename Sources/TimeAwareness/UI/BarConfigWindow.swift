import Cocoa
import SwiftUI

// MARK: - Window Controller

/// Manages a standalone macOS window for editing bar configurations.
/// This replaces the cramped inline bar editor in SettingsView.
class BarConfigWindowController {
    static let shared = BarConfigWindowController()
    
    private var window: NSWindow?
    private var hostingView: NSHostingView<BarConfigView>?
    
    private init() {}
    
    func show() {
        // If already open, just bring to front
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let config = ConfigManager.shared.config
        let contentView = BarConfigView(
            bars: config.bars,
            onSave: { [weak self] updatedBars in
                self?.handleSave(updatedBars)
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )
        
        let hosting = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure Bars"
        window.contentView = hosting
        window.minSize = NSSize(width: 500, height: 300)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
        self.hostingView = hosting
    }
    
    private func handleSave(_ updatedBars: [BarConfig]) {
        var config = ConfigManager.shared.config
        config.bars = updatedBars
        ConfigManager.shared.save(config)
        window?.close()
    }
}

// MARK: - SwiftUI View

struct BarConfigView: View {
    @State var bars: [BarConfig]
    let onSave: ([BarConfig]) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Bar Configuration")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text("\(bars.count) bars")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Column headers
            barHeaderRow
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 4)
            
            // Scrollable bar list
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    ForEach(bars.indices, id: \.self) { index in
                        barEditorRow(index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            // Bottom bar: Add + Save/Cancel
            HStack(spacing: 12) {
                Button(action: addBar) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Bar")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    onSave(bars)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 300)
    }
    
    // MARK: - Column Headers
    
    private var barHeaderRow: some View {
        HStack(spacing: 6) {
            Text("Name")
                .frame(width: 70, alignment: .leading)
            Text("Rule")
                .frame(width: 70, alignment: .leading)
            Text("Color")
                .frame(width: 90, alignment: .leading)
            Text("")
                .frame(width: 10) // color dot
            Text("Thk")
                .frame(width: 36, alignment: .center)
            Text("Seg")
                .frame(width: 24, alignment: .center)
            Text("#")
                .frame(width: 32, alignment: .center)
            Text("Ntf")
                .frame(width: 24, alignment: .center)
            Text("Idle")
                .frame(width: 28, alignment: .center)
            Text("Exp")
                .frame(width: 28, alignment: .center)
            Text("") // delete
                .frame(width: 20)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundColor(.secondary)
    }
    
    // MARK: - Bar Editor Row
    
    @ViewBuilder
    private func barEditorRow(index: Int) -> some View {
        HStack(spacing: 6) {
            // Name
            TextField("name", text: $bars[index].name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: 70)
            
            // Rule
            TextField("rule", text: $bars[index].rule)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 70)
            
            // Color
            TextField("color", text: $bars[index].color)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ColorParser.parse(bars[index].color))
                .frame(width: 90)
            
            // Color preview dot
            Circle()
                .fill(ColorParser.parse(bars[index].color))
                .frame(width: 10, height: 10)
            
            // Thickness
            TextField("4", text: Binding(
                get: { String(Int(bars[index].thickness)) },
                set: { bars[index].thickness = CGFloat(Int($0) ?? 4) }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 36)
                .multilineTextAlignment(.center)
            
            // Segmented toggle
            Button(action: {
                bars[index].segmented.toggle()
            }) {
                Image(systemName: bars[index].segmented ? "square.grid.3x3.fill" : "square.grid.3x3")
                    .font(.system(size: 12))
                    .foregroundColor(bars[index].segmented ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            
            // Segment count
            if bars[index].segmented {
                TextField("20", text: Binding(
                    get: { String(bars[index].segments) },
                    set: { bars[index].segments = max(2, Int($0) ?? 20) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 32)
                    .multilineTextAlignment(.center)
            } else {
                Spacer().frame(width: 32)
            }
            
            // Notify toggle
            Button(action: {
                bars[index].notify.toggle()
            }) {
                Image(systemName: bars[index].notify ? "bell.fill" : "bell.slash")
                    .font(.system(size: 12))
                    .foregroundColor(bars[index].notify ? .yellow : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 24)
            
            // Show in Idle toggle
            Button(action: {
                bars[index].showInIdle.toggle()
            }) {
                Image(systemName: bars[index].showInIdle ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(bars[index].showInIdle ? .green : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .help("Show in idle (compact) state")
            
            // Show in Expanded toggle
            Button(action: {
                bars[index].showInExpanded.toggle()
            }) {
                Image(systemName: bars[index].showInExpanded ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundColor(bars[index].showInExpanded ? .blue : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .help("Show in expanded state")
            
            // Delete
            if bars.count > 1 {
                Button(action: {
                    bars.remove(at: index)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            } else {
                Spacer().frame(width: 20)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.03))
        )
    }
    
    // MARK: - Actions
    
    private func addBar() {
        let newBar = BarConfig(
            name: "bar_\(bars.count)",
            rule: Defaults.barRule,
            color: Defaults.barColor,
            thickness: Defaults.barThickness,
            segmented: Defaults.barSegmented,
            segments: Defaults.barSegments,
            notify: Defaults.barNotify,
            showInIdle: Defaults.barShowInIdle,
            showInExpanded: Defaults.barShowInExpanded
        )
        bars.append(newBar)
    }
}
