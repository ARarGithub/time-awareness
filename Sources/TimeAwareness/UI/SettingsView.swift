import SwiftUI

/// Inline settings editor displayed inside the expanded Dynamic Island.
struct SettingsView: View {
    @ObservedObject var viewModel: DynamicIslandViewModel

    private enum Style {
        static let headerFontSize: CGFloat = 12
        static let headerOpacity: Double = 0.9
        static let sectionTitleFontSize: CGFloat = 8
        static let sectionTitleOpacity: Double = 0.3
        static let sectionTitleTracking: CGFloat = 1
        static let sectionCornerRadius: CGFloat = 6
        static let sectionBackgroundOpacity: Double = 0.03
        static let fieldLabelFontSize: CGFloat = 9
        static let fieldLabelOpacity: Double = 0.45
        static let fieldTextFontSize: CGFloat = 9
        static let fieldTextOpacity: Double = 0.8
        static let fieldPaddingHorizontal: CGFloat = 4
        static let fieldPaddingVertical: CGFloat = 2
        static let fieldCornerRadius: CGFloat = 4
        static let toggleLabelFontSize: CGFloat = 9
        static let toggleLabelOpacity: Double = 0.45
        static let toggleValueFontSize: CGFloat = 9
        static let toggleActiveOpacity: Double = 0.9
        static let toggleInactiveOpacity: Double = 0.4
        static let togglePaddingHorizontal: CGFloat = 5
        static let togglePaddingVertical: CGFloat = 2
        static let toggleCornerRadius: CGFloat = 4
        static let toggleBackgroundOpacity: Double = 0.06
        static let barsCountFontSize: CGFloat = 10
        static let barsCountOpacity: Double = 0.6
        static let configureButtonFontSize: CGFloat = 10
        static let configureButtonOpacity: Double = 0.85
        static let configureButtonPaddingHorizontal: CGFloat = 8
        static let configureButtonPaddingVertical: CGFloat = 4
        static let configureButtonCornerRadius: CGFloat = 6
        static let configureButtonBackgroundOpacity: Double = 0.06
        static let actionButtonFontSize: CGFloat = 11
        static let actionButtonOpacity: Double = 0.6
        static let actionButtonPaddingHorizontal: CGFloat = 10
        static let actionButtonPaddingVertical: CGFloat = 4
        static let actionButtonBackgroundOpacity: Double = 0.08
        static let saveButtonFontSize: CGFloat = 11
        static let saveButtonPaddingHorizontal: CGFloat = 12
        static let saveButtonPaddingVertical: CGFloat = 4
        static let saveButtonGreenBackgroundOpacity: Double = 0.15
        static let saveButtonCyanBackgroundOpacity: Double = 0.2
        static let saveButtonStrokeOpacity: Double = 0.3
        static let saveButtonStrokeWidth: CGFloat = 0.5
        static let fieldWidthIdle: CGFloat = 40
        static let fieldWidthExpand: CGFloat = 40
        static let fieldWidthName: CGFloat = 32
        static let fieldWidthTimeSize: CGFloat = 32
        static let defaultBarLength: CGFloat = 200
        static let defaultBarLengthExpanded: CGFloat = 300
        static let defaultNameSize: CGFloat = 10
        static let defaultTimeTextSize: CGFloat = 14
        static let placeholderIdle: String = "200"
        static let placeholderExpand: String = "300"
        static let placeholderName: String = "10"
        static let placeholderTimeSize: String = "14"
        static let saveAnimationResponse: Double = 0.3
        static let saveAnimationDamping: Double = 0.7
        static let saveResetDelay: Double = 1.5
    }
    
    @State private var editableAnimation: AnimationConfig = .defaultAnimation
    @State private var editableBarLength: CGFloat = Style.defaultBarLength
    @State private var editableBarLengthExpanded: CGFloat = Style.defaultBarLengthExpanded
    @State private var editableNameSize: CGFloat = Style.defaultNameSize
    @State private var editableTimeTextSize: CGFloat = Style.defaultTimeTextSize
    @State private var editableTimeFormat: String = "24h"
    @State private var editableTimeShowSeconds: Bool = true
    @State private var showSaved: Bool = false
    
    var body: some View {
        VStack(spacing: viewModel.settingsContentSpacing) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: Style.headerFontSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(Style.headerOpacity))
                Spacer()
            }
            
            // Display section
            VStack(spacing: viewModel.settingsSectionSpacing) {
                HStack {
                    Text("DISPLAY")
                        .font(.system(size: Style.sectionTitleFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(Style.sectionTitleOpacity))
                        .tracking(Style.sectionTitleTracking)
                    Spacer()
                }
                HStack(spacing: viewModel.settingsFieldRowSpacing) {
                    settingsField("Idle", value: $editableBarLength, placeholder: Style.placeholderIdle, width: Style.fieldWidthIdle)
                    settingsField("Expand", value: $editableBarLengthExpanded, placeholder: Style.placeholderExpand, width: Style.fieldWidthExpand)
                    settingsField("Name", value: $editableNameSize, placeholder: Style.placeholderName, width: Style.fieldWidthName)
                    Spacer()
                }
            }
            .padding(.horizontal, viewModel.settingsSectionPaddingHorizontal)
            .padding(.vertical, viewModel.settingsSectionPaddingVertical)
            .background(RoundedRectangle(cornerRadius: Style.sectionCornerRadius).fill(Color.white.opacity(Style.sectionBackgroundOpacity)))
            
            // Time section
            VStack(spacing: viewModel.settingsSectionSpacing) {
                HStack {
                    Text("TIME")
                        .font(.system(size: Style.sectionTitleFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(Style.sectionTitleOpacity))
                        .tracking(Style.sectionTitleTracking)
                    Spacer()
                }
                HStack(spacing: viewModel.settingsFieldRowSpacing) {
                    settingsField("Size", value: $editableTimeTextSize, placeholder: Style.placeholderTimeSize, width: Style.fieldWidthTimeSize)
                    
                    HStack(spacing: viewModel.settingsToggleSpacing) {
                        Text("Format")
                            .font(.system(size: Style.toggleLabelFontSize, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(Style.toggleLabelOpacity))
                        Button(action: {
                            editableTimeFormat = editableTimeFormat == "24h" ? "12h" : "24h"
                        }) {
                            Text(editableTimeFormat)
                                .font(.system(size: Style.toggleValueFontSize, weight: .semibold, design: .monospaced))
                                .foregroundColor(.cyan.opacity(Style.toggleActiveOpacity))
                                .padding(.horizontal, Style.togglePaddingHorizontal)
                                .padding(.vertical, Style.togglePaddingVertical)
                                .background(RoundedRectangle(cornerRadius: Style.toggleCornerRadius).fill(Color.white.opacity(Style.toggleBackgroundOpacity)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    HStack(spacing: viewModel.settingsToggleSpacing) {
                        Text("Sec")
                            .font(.system(size: Style.toggleLabelFontSize, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(Style.toggleLabelOpacity))
                        Button(action: {
                            editableTimeShowSeconds.toggle()
                        }) {
                            Text(editableTimeShowSeconds ? "ON" : "OFF")
                                .font(.system(size: Style.toggleValueFontSize, weight: .semibold, design: .monospaced))
                                .foregroundColor(editableTimeShowSeconds ? .cyan.opacity(Style.toggleActiveOpacity) : .white.opacity(Style.toggleInactiveOpacity))
                                .padding(.horizontal, Style.togglePaddingHorizontal)
                                .padding(.vertical, Style.togglePaddingVertical)
                                .background(RoundedRectangle(cornerRadius: Style.toggleCornerRadius).fill(Color.white.opacity(Style.toggleBackgroundOpacity)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, viewModel.settingsSectionPaddingHorizontal)
            .padding(.vertical, viewModel.settingsSectionPaddingVertical)
            .background(RoundedRectangle(cornerRadius: Style.sectionCornerRadius).fill(Color.white.opacity(Style.sectionBackgroundOpacity)))
            
            // Bars section (opens separate window to avoid cramped inline editor)
            VStack(spacing: viewModel.settingsSectionSpacing) {
                HStack {
                    Text("BARS")
                        .font(.system(size: Style.sectionTitleFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(Style.sectionTitleOpacity))
                        .tracking(Style.sectionTitleTracking)
                    Spacer()
                }
                HStack(spacing: viewModel.settingsBarsRowSpacing) {
                    Text("\(viewModel.bars.count) bars")
                        .font(.system(size: Style.barsCountFontSize, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(Style.barsCountOpacity))
                    Spacer()
                    Button(action: {
                        BarConfigWindowController.shared.show()
                    }) {
                        HStack(spacing: viewModel.settingsButtonContentSpacing) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: Style.configureButtonFontSize))
                            Text("Configure")
                                .font(.system(size: Style.configureButtonFontSize, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.cyan.opacity(Style.configureButtonOpacity))
                        .padding(.horizontal, Style.configureButtonPaddingHorizontal)
                        .padding(.vertical, Style.configureButtonPaddingVertical)
                        .background(RoundedRectangle(cornerRadius: Style.configureButtonCornerRadius).fill(Color.white.opacity(Style.configureButtonBackgroundOpacity)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, viewModel.settingsSectionPaddingHorizontal)
            .padding(.vertical, viewModel.settingsSectionPaddingVertical)
            .background(RoundedRectangle(cornerRadius: Style.sectionCornerRadius).fill(Color.white.opacity(Style.sectionBackgroundOpacity)))
            
            // Action buttons
            HStack(spacing: viewModel.settingsActionSpacing) {
                Spacer()
                
                Button("Cancel") {
                    viewModel.transitionTo(.expanded)
                }
                .font(.system(size: Style.actionButtonFontSize, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(Style.actionButtonOpacity))
                .padding(.horizontal, Style.actionButtonPaddingHorizontal)
                .padding(.vertical, Style.actionButtonPaddingVertical)
                .background(Capsule().fill(Color.white.opacity(Style.actionButtonBackgroundOpacity)))
                .buttonStyle(.plain)
                
                Button(action: saveConfig) {
                    HStack(spacing: viewModel.settingsToggleSpacing) {
                        if showSaved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: Style.saveButtonFontSize))
                                .foregroundColor(.green)
                        }
                        Text(showSaved ? "Saved!" : "Save")
                            .font(.system(size: Style.saveButtonFontSize, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(showSaved ? .green : .white)
                    .padding(.horizontal, Style.saveButtonPaddingHorizontal)
                    .padding(.vertical, Style.saveButtonPaddingVertical)
                    .background(
                        Capsule().fill(showSaved ? Color.green.opacity(Style.saveButtonGreenBackgroundOpacity) : Color.cyan.opacity(Style.saveButtonCyanBackgroundOpacity))
                    )
                    .overlay(
                        Capsule().strokeBorder(showSaved ? Color.green.opacity(Style.saveButtonStrokeOpacity) : Color.cyan.opacity(Style.saveButtonStrokeOpacity), lineWidth: Style.saveButtonStrokeWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, viewModel.settingsPaddingHorizontal)
        .padding(.top, viewModel.settingsPaddingTop)
        .padding(.bottom, viewModel.settingsPaddingBottom)
        .onAppear {
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
        HStack(spacing: viewModel.settingsFieldLabelSpacing) {
            Text(label)
                .font(.system(size: Style.fieldLabelFontSize, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(Style.fieldLabelOpacity))
            TextField(placeholder, text: Binding(
                get: { String(Int(value.wrappedValue)) },
                set: { value.wrappedValue = CGFloat(Int($0) ?? Int(placeholder) ?? 0) }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: Style.fieldTextFontSize, design: .monospaced))
                .foregroundColor(.white.opacity(Style.fieldTextOpacity))
                .padding(.horizontal, Style.fieldPaddingHorizontal)
                .padding(.vertical, Style.fieldPaddingVertical)
                .frame(width: width)
                .background(RoundedRectangle(cornerRadius: Style.fieldCornerRadius).fill(Color.white.opacity(Style.toggleBackgroundOpacity)))
                .multilineTextAlignment(.center)
        }
    }
    
    private func saveConfig() {
        let newConfig = AppConfig(
            bars: viewModel.bars,
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
        
        withAnimation(.spring(response: Style.saveAnimationResponse, dampingFraction: Style.saveAnimationDamping)) {
            showSaved = true
        }
        
        // Reset "Saved!" indicator after 1.5s but stay in settings
        DispatchQueue.main.asyncAfter(deadline: .now() + Style.saveResetDelay) {
            withAnimation {
                showSaved = false
            }
        }
    }
}
