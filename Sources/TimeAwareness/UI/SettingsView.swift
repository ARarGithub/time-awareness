import SwiftUI

/// Inline settings editor displayed inside the expanded Dynamic Island.
struct SettingsView: View {
    @ObservedObject var viewModel: DynamicIslandViewModel
    
    @State private var editableBars: [BarConfig] = []
    @State private var editableAnimation: AnimationConfig = .defaultAnimation
    @State private var editableBarLength: CGFloat = 200
    @State private var editableBarLengthExpanded: CGFloat = 300
    @State private var editableNameSize: CGFloat = 10
    @State private var editableTimeTextSize: CGFloat = 14
    @State private var editableTimeFormat: String = "24h"
    @State private var editableTimeShowSeconds: Bool = true
    @State private var showSaved: Bool = false
    
    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            
            // Display section
            VStack(spacing: 4) {
                HStack {
                    Text("DISPLAY")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                    Spacer()
                }
                HStack(spacing: 10) {
                    settingsField("Idle", value: $editableBarLength, placeholder: "200", width: 40)
                    settingsField("Expand", value: $editableBarLengthExpanded, placeholder: "300", width: 40)
                    settingsField("Name", value: $editableNameSize, placeholder: "10", width: 32)
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
            
            // Time section
            VStack(spacing: 4) {
                HStack {
                    Text("TIME")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                    Spacer()
                }
                HStack(spacing: 10) {
                    settingsField("Size", value: $editableTimeTextSize, placeholder: "14", width: 32)
                    
                    HStack(spacing: 3) {
                        Text("Format")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                        Button(action: {
                            editableTimeFormat = editableTimeFormat == "24h" ? "12h" : "24h"
                        }) {
                            Text(editableTimeFormat)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: 3) {
                        Text("Sec")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                        Button(action: {
                            editableTimeShowSeconds.toggle()
                        }) {
                            Text(editableTimeShowSeconds ? "ON" : "OFF")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(editableTimeShowSeconds ? .cyan.opacity(0.9) : .white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
            
            // Bar editor list (headers + fields in same container for alignment)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    // Column headers — inside scroll so they align with fields
                    barHeaderRow
                    
                    ForEach(editableBars.indices, id: \.self) { index in
                        barEditor(index: index)
                    }
                    
                    // Add bar button
                    Button(action: addBar) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                            Text("Add Bar")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.cyan.opacity(0.8))
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: 160)
            
            // Action buttons
            HStack(spacing: 8) {
                Spacer()
                
                Button("Cancel") {
                    viewModel.transitionTo(.expanded)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .buttonStyle(.plain)
                
                Button(action: saveConfig) {
                    HStack(spacing: 3) {
                        if showSaved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                        Text(showSaved ? "Saved!" : "Save")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(showSaved ? .green : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(showSaved ? Color.green.opacity(0.15) : Color.cyan.opacity(0.2))
                    )
                    .overlay(
                        Capsule().strokeBorder(showSaved ? Color.green.opacity(0.3) : Color.cyan.opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .onAppear {
            editableBars = viewModel.bars
            editableAnimation = viewModel.animationConfig
            editableBarLength = viewModel.barLength
            editableBarLengthExpanded = viewModel.barLengthExpanded
            editableNameSize = viewModel.nameSize
            editableTimeTextSize = viewModel.timeTextSize
            editableTimeFormat = viewModel.timeFormat
            editableTimeShowSeconds = viewModel.timeShowSeconds
        }
    }
    
    // MARK: - Reusable Settings Field
    
    @ViewBuilder
    private func settingsField(_ label: String, value: Binding<CGFloat>, placeholder: String, width: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.45))
            TextField(placeholder, text: Binding(
                get: { String(Int(value.wrappedValue)) },
                set: { value.wrappedValue = CGFloat(Int($0) ?? Int(placeholder) ?? 0) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Column Header Row (same HStack structure as barEditor)
    
    private var barHeaderRow: some View {
        HStack(spacing: 4) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Rule")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Color")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("")
                .frame(width: 8) // dot column
            Text("Thk")
                .frame(width: 36, alignment: .center)
            Text("Seg")
                .frame(width: 20, alignment: .center)
            Text("#")
                .frame(width: 28, alignment: .center)
            Text("Ntf")
                .frame(width: 20, alignment: .center)
            // Spacer for delete button column
            Text("")
                .frame(width: 16)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundColor(.white.opacity(0.35))
        .padding(.horizontal, 4)
    }
    
    // MARK: - Bar Editor Row (flexible widths)
    
    @ViewBuilder
    private func barEditor(index: Int) -> some View {
        HStack(spacing: 4) {
            // Name
            TextField("name", text: $editableBars[index].name)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            
            // Rule
            TextField("rule", text: $editableBars[index].rule)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.cyan.opacity(0.9))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            
            // Color
            TextField("color", text: $editableBars[index].color)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ColorParser.parse(editableBars[index].color))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            
            // Color preview dot
            Circle()
                .fill(ColorParser.parse(editableBars[index].color))
                .frame(width: 8, height: 8)
            
            // Thickness
            TextField("4", text: Binding(
                get: { String(Int(editableBars[index].thickness)) },
                set: { editableBars[index].thickness = CGFloat(Int($0) ?? 4) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(width: 36)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                .multilineTextAlignment(.center)
            
            // Segmented toggle
            Button(action: {
                editableBars[index].segmented.toggle()
            }) {
                Image(systemName: editableBars[index].segmented ? "square.grid.3x3.fill" : "square.grid.3x3")
                    .font(.system(size: 10))
                    .foregroundColor(editableBars[index].segmented ? .cyan.opacity(0.9) : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            
            // Segment count (always reserves space for alignment)
            if editableBars[index].segmented {
                TextField("20", text: Binding(
                    get: { String(editableBars[index].segments) },
                    set: { editableBars[index].segments = max(2, Int($0) ?? 20) }
                ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.7))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .frame(width: 28)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                    .multilineTextAlignment(.center)
            } else {
                Spacer().frame(width: 28)
            }
            
            // Notify toggle
            Button(action: {
                editableBars[index].notify.toggle()
            }) {
                Image(systemName: editableBars[index].notify ? "bell.fill" : "bell.slash")
                    .font(.system(size: 10))
                    .foregroundColor(editableBars[index].notify ? .yellow.opacity(0.9) : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            
            // Delete
            if editableBars.count > 1 {
                Button(action: {
                    editableBars.remove(at: index)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }
        }
    }
    
    // MARK: - Actions
    
    private func addBar() {
        let newBar = BarConfig(
            name: "bar_\(editableBars.count)",
            rule: Defaults.barRule,
            color: Defaults.barColor,
            thickness: Defaults.barThickness,
            segmented: Defaults.barSegmented,
            segments: Defaults.barSegments,
            notify: Defaults.barNotify
        )
        editableBars.append(newBar)
    }
    
    private func saveConfig() {
        let newConfig = AppConfig(
            bars: editableBars,
            animation: editableAnimation,
            barLength: editableBarLength,
            barLengthExpanded: editableBarLengthExpanded,
            nameSize: editableNameSize,
            timeTextSize: editableTimeTextSize,
            timeFormat: editableTimeFormat,
            timeShowSeconds: editableTimeShowSeconds
        )
        ConfigManager.shared.save(newConfig)
        viewModel.reloadConfig()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showSaved = true
        }
        
        // Reset "Saved!" indicator after 1.5s but stay in settings
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showSaved = false
            }
        }
    }
}
