import SwiftUI
import Combine

// MARK: - State

enum IslandState: Equatable {
    case idle
    case hovered
    case expanded
    case settings
}

// MARK: - ViewModel

class DynamicIslandViewModel: ObservableObject {
    static let defaultBarLength: CGFloat = 200
    static let defaultBarLengthExpanded: CGFloat = 300
    static let defaultNameSize: CGFloat = 10
    static let defaultTimeTextSize: CGFloat = 14

    @Published var state: IslandState = .idle
    @Published var barProgresses: [String: Double] = [:]
    @Published var bars: [BarConfig] = []
    @Published var animationConfig: AnimationConfig = .defaultAnimation
    @Published var barLength: CGFloat = DynamicIslandViewModel.defaultBarLength
    @Published var barLengthExpanded: CGFloat = DynamicIslandViewModel.defaultBarLengthExpanded
    @Published var nameSize: CGFloat = DynamicIslandViewModel.defaultNameSize
    @Published var timeTextSize: CGFloat = DynamicIslandViewModel.defaultTimeTextSize
    @Published var timeFormat: String = "24h"
    @Published var timeShowSeconds: Bool = true
    @Published var currentTimeString: String = ""
    
    /// Pre-parsed colors keyed by bar name — avoids repeated ColorParser.parse() in view body
    private(set) var cachedColors: [String: Color] = [:]
    /// Time units keyed by bar name — used to adapt animation curves
    private(set) var barUnits: [String: TimeRule.Unit] = [:]
    
    private let tickManager = TickManager()
    private var rules: [String: TimeRule] = [:]
    private var barConfigMap: [String: BarConfig] = [:]  // O(1) lookup
    private var notificationDismissWork: DispatchWorkItem?
    /// True while an auto-notification hover is active (prevents mouse-leave from dismissing)
    private(set) var isNotifying: Bool = false
    private let timeDisplayRegistrationName = "__time_display__"
    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var idleBars: [BarConfig] {
        bars.filter { $0.showInIdle }
    }

    private var expandedBars: [BarConfig] {
        bars.filter { $0.showInExpanded }
    }

    var idleBarGap: CGFloat { 2 }
    var idlePaddingTop: CGFloat { 2 }
    var idlePaddingBottom: CGFloat { 2 }
    var idlePaddingHorizontal: CGFloat { 16 }

    var hoveredContentSpacing: CGFloat { 4 }
    var hoveredPaddingTop: CGFloat { 16 }
    var hoveredPaddingBottom: CGFloat { 14 }
    var hoveredPaddingHorizontal: CGFloat { 20 }

    var expandedContentSpacing: CGFloat { 6 }
    var expandedPaddingTop: CGFloat { 14 }
    var expandedPaddingBottom: CGFloat { 12 }
    var expandedPaddingHorizontal: CGFloat { 20 }
    var expandedButtonRowHeight: CGFloat { 36 }
    var expandedButtonSpacing: CGFloat { 12 }

    var settingsContentSpacing: CGFloat { 6 }
    var settingsSectionSpacing: CGFloat { 4 }
    var settingsPaddingTop: CGFloat { 12 }
    var settingsPaddingBottom: CGFloat { 10 }
    var settingsPaddingHorizontal: CGFloat { 16 }
    var settingsSectionPaddingHorizontal: CGFloat { 8 }
    var settingsSectionPaddingVertical: CGFloat { 5 }
    var settingsActionSpacing: CGFloat { 8 }
    var settingsFieldRowSpacing: CGFloat { 10 }
    var settingsFieldLabelSpacing: CGFloat { 3 }
    var settingsToggleSpacing: CGFloat { 3 }
    var settingsBarsRowSpacing: CGFloat { 8 }
    var settingsButtonContentSpacing: CGFloat { 4 }
    var settingsWidthPadding: CGFloat { 40 }
    var settingsMinWidth: CGFloat { 340 }
    var settingsHeight: CGFloat { 200 }

    var barLabelHeightPadding: CGFloat { 4 }
    var barLabelToBarSpacing: CGFloat { 3 }
    var barThicknessFallback: CGFloat { 4 }
    var idleMinWidth: CGFloat { 100 }
    var idleMinHeight: CGFloat { 30 }
    var hoveredMinWidth: CGFloat { 140 }
    var hoveredMinHeight: CGFloat { 48 }
    var expandedMinWidth: CGFloat { 200 }
    var expandedMinHeight: CGFloat { 80 }

    var barCountMinimum: Int { 1 }
    var barGapMinimum: Int { 0 }
    var progressUnsetValue: Double { -1 }
    var progressZeroValue: Double { 0 }
    var segmentedDefaultSegments: Int { 20 }
    var unsegmentedBucketCount: Int { 100 }
    var notificationWrapThreshold: Double { 0.5 }
    var progressFullValue: Double { 1.0 }
    var notificationAutoDismissSeconds: Double { 3 }
    
    init() {
        tickManager.onTick = { [weak self] date, changed in
            self?.handleTick(at: date, changed: changed)
        }
        reloadConfig()
        updateTickRegistrations()
    }
    
    deinit {
    }
    
    func reloadConfig() {
        let config = ConfigManager.shared.config
        bars = config.bars
        animationConfig = config.animation
        barLength = config.barLength
        barLengthExpanded = config.barLengthExpanded
        nameSize = config.nameSize
        timeTextSize = config.timeTextSize
        timeFormat = config.timeFormat
        timeShowSeconds = config.timeShowSeconds
        
        // Update time formatter
        if timeFormat == "12h" {
            timeFormatter.dateFormat = timeShowSeconds ? "h:mm:ss a" : "h:mm a"
        } else {
            timeFormatter.dateFormat = timeShowSeconds ? "HH:mm:ss" : "HH:mm"
        }
        
        // Parse all rules and cache colors
        rules = [:]
        cachedColors = [:]
        barUnits = [:]
        barConfigMap = [:]
        for bar in config.bars {
            cachedColors[bar.name] = ColorParser.parse(bar.color)
            barConfigMap[bar.name] = bar
            if let rule = TimeRule.parse(bar.rule) {
                rules[bar.name] = rule
                barUnits[bar.name] = rule.unit
            }
        }
        
        updateTickRegistrations()
    }
    
    func transitionTo(_ newState: IslandState) {
        withAnimation(.spring(
            response: animationConfig.expandSpringResponse,
            dampingFraction: animationConfig.expandSpringDamping
        )) {
            state = newState
        }
        updateTickRegistrations()
    }
    
    // MARK: - Sizing (these are the CONTENT pill sizes, not including the top flare)
    
    var currentPillSize: CGSize {
        switch state {
        case .idle:
            return idleSize
        case .hovered:
            return hoveredSize
        case .expanded:
            return expandedSize
        case .settings:
            return settingsSize
        }
    }
    
    var idleSize: CGSize {
        let visibleBars = idleBars
        let barCount = max(visibleBars.count, barCountMinimum)
        let totalThickness = visibleBars.reduce(CGFloat(0)) { $0 + $1.thickness }
        let gaps = CGFloat(max(barCount - 1, barGapMinimum)) * idleBarGap
        let height: CGFloat = idlePaddingTop + totalThickness + gaps + idlePaddingBottom
        // Idle width = barLength + horizontal padding (2 * 16)
        let width: CGFloat = barLength + (idlePaddingHorizontal * 2)
        return CGSize(width: max(width, idleMinWidth), height: max(height, idleMinHeight))
    }
    
    var hoveredSize: CGSize {
        let visibleBars = expandedBars
        let barCount = max(visibleBars.count, barCountMinimum)
        let labelHeight: CGFloat = nameSize + barLabelHeightPadding  // label line height
        let barRowHeight: CGFloat = labelHeight + barLabelToBarSpacing + max(visibleBars.map({ $0.thickness }).max() ?? barThicknessFallback, barThicknessFallback)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * hoveredContentSpacing
        let timeHeight: CGFloat = timeTextSize + hoveredContentSpacing  // time text + spacing
        let height: CGFloat = hoveredPaddingTop + timeHeight + barHeight + hoveredPaddingBottom
        let width: CGFloat = barLengthExpanded + (hoveredPaddingHorizontal * 2)
        return CGSize(width: max(width, hoveredMinWidth), height: max(height, hoveredMinHeight))
    }
    
    var expandedSize: CGSize {
        let visibleBars = expandedBars
        let barCount = max(visibleBars.count, barCountMinimum)
        let labelHeight: CGFloat = nameSize + barLabelHeightPadding
        let barRowHeight: CGFloat = labelHeight + barLabelToBarSpacing + max(visibleBars.map({ $0.thickness }).max() ?? barThicknessFallback, barThicknessFallback)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * expandedContentSpacing
        let timeHeight: CGFloat = timeTextSize + expandedContentSpacing  // time text + spacing below
        let height: CGFloat = expandedPaddingTop + timeHeight + barHeight + expandedContentSpacing + expandedButtonRowHeight + expandedPaddingBottom
        let width: CGFloat = barLengthExpanded + (expandedPaddingHorizontal * 2)
        return CGSize(width: max(width, expandedMinWidth), height: max(height, expandedMinHeight))
    }
    
    var settingsSize: CGSize {
        let width: CGFloat = max(barLengthExpanded + settingsWidthPadding, settingsMinWidth)
        return CGSize(width: width, height: settingsHeight)
    }
    
    // MARK: - Tick Manager
    
    private func handleTick(at now: Date, changed: Set<TickGranularity>) {
        updateProgress(at: now, changed: changed)
    }
    
    private func updateTickRegistrations() {
        var registrations: [String: TickGranularity] = [:]
        
        for bar in visibleBarsForCurrentState() {
            guard let rule = rules[bar.name] else { continue }
            registrations[bar.name] = granularity(for: rule)
        }
        
        if shouldShowTimeDisplay(for: state) {
            registrations[timeDisplayRegistrationName] = timeDisplayGranularity()
        }
        
        tickManager.setRegistrations(registrations)
        let updateGranularities = Set(registrations.values)
        if !updateGranularities.isEmpty {
            updateProgress(at: Date(), changed: updateGranularities)
        }
    }
    
    private func updateProgress(at now: Date, changed: Set<TickGranularity>) {
        let visibleNames = Set(visibleBarsForCurrentState().map { $0.name })
        var updates: [String: Double] = [:]
        
        for name in visibleNames {
            guard let rule = rules[name] else { continue }
            let ruleGranularity = granularity(for: rule)
            guard changed.contains(ruleGranularity) else { continue }
            
            let newValue = rule.progress(at: now)
            let oldValue = barProgresses[name] ?? progressUnsetValue
            let isSegmented = barConfigMap[name]?.segmented ?? false
            let segments = barConfigMap[name]?.segments ?? segmentedDefaultSegments
            let bucketCount = isSegmented ? segments : unsegmentedBucketCount
            let forceValueUpdate = isSegmented && (rule.unit == .seconds || rule.unit == .minutes)
            if forceValueUpdate || Int(newValue * Double(bucketCount)) != Int(oldValue * Double(bucketCount)) {
                updates[name] = newValue
            }
        }
        
        var updatedTimeString: String?
        if shouldShowTimeDisplay(for: state) {
            let timeGranularity = timeDisplayGranularity()
            if changed.contains(timeGranularity) {
                let newTimeString = timeFormatter.string(from: now)
                if newTimeString != currentTimeString {
                    updatedTimeString = newTimeString
                }
            }
        }
        
        guard !updates.isEmpty || updatedTimeString != nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let updatedTimeString = updatedTimeString {
                self.currentTimeString = updatedTimeString
            }
            
            // Check for notification: any bar with notify=true just completed a cycle.
            var shouldNotify = false
            for (name, value) in updates {
                let oldValue = self.barProgresses[name] ?? progressUnsetValue
                let bar = self.barConfigMap[name]
                if bar?.notify == true && oldValue >= progressZeroValue {
                    let cycleCompleted = (oldValue - value) > notificationWrapThreshold  // wrap-around detected
                    let reachedFull = value >= progressFullValue && oldValue < progressFullValue
                    if cycleCompleted || reachedFull {
                        shouldNotify = true
                    }
                }
                self.barProgresses[name] = value
            }
            
            if shouldNotify && self.state == .idle {
                // Cancel any pending dismiss
                self.notificationDismissWork?.cancel()
                
                self.isNotifying = true
                self.transitionTo(.hovered)
                
                // Auto-dismiss after a short delay
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.isNotifying = false
                    if self.state == .hovered {
                        self.transitionTo(.idle)
                    }
                }
                self.notificationDismissWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + notificationAutoDismissSeconds, execute: work)
            }
        }
    }
    
    private func visibleBarsForCurrentState() -> [BarConfig] {
        switch state {
        case .idle:
            return idleBars
        case .hovered, .expanded:
            return expandedBars
        case .settings:
            return []
        }
    }
    
    private func shouldShowTimeDisplay(for state: IslandState) -> Bool {
        state == .hovered || state == .expanded
    }
    
    private func timeDisplayGranularity() -> TickGranularity {
        timeShowSeconds ? .second : .minute
    }
    
    private func granularity(for rule: TimeRule) -> TickGranularity {
        switch rule.unit {
        case .seconds:
            return .second
        case .minutes:
            return .minute
        case .hours:
            return .hour
        case .days, .week, .month, .year:
            return .day
        }
    }
}

// MARK: - Dynamic Island Shape
//
// This shape creates the "dripping from screen edge" look:
//   - The top edge is WIDER than the pill body (flares outward)
//   - Smooth cubic curves connect the wide top to the narrower body
//   - No rounding on top corners — straight flush with the screen edge
//   - Rounded corners only on the bottom
//
// Visually (cross-section):
//
//   ████████████████████████████  ← wide top, flush with screen
//    ╲                        ╱   ← smooth taper inward
//     ╲                      ╱
//      ┃                    ┃     ← main body
//      ┃                    ┃
//       ╰────────────────╯        ← rounded bottom

struct DynamicIslandShape: Shape {
    var bottomRadius: CGFloat
    /// Extra width on each side at the top (the "flare")
    var topFlare: CGFloat

    private enum ShapeConstants {
        static let neckHeightRatio: CGFloat = 0.25
        static let neckHeightMax: CGFloat = 20
        static let taperControlOuter: CGFloat = 0.3
        static let taperControlInner: CGFloat = 0.5
    }
    
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topFlare) }
        set {
            bottomRadius = newValue.first
            topFlare = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let r = min(bottomRadius, w / 2, h / 2)
        let flare = topFlare
        
        // The "neck" height — how far down the taper extends
        let neckHeight: CGFloat = min(h * ShapeConstants.neckHeightRatio, ShapeConstants.neckHeightMax)
        
        // Top-left corner (extended outward by flare)
        path.move(to: CGPoint(x: -flare, y: 0))
        
        // Top edge — straight, wider than the body
        path.addLine(to: CGPoint(x: w + flare, y: 0))
        
        // Right taper: from (w + flare, 0) curving inward to (w, neckHeight)
        path.addCurve(
            to: CGPoint(x: w, y: neckHeight),
            control1: CGPoint(x: w + flare, y: neckHeight * ShapeConstants.taperControlOuter),
            control2: CGPoint(x: w, y: neckHeight * ShapeConstants.taperControlInner)
        )
        
        // Right side straight down to bottom-right corner
        path.addLine(to: CGPoint(x: w, y: h - r))
        
        // Bottom-right arc
        path.addArc(
            center: CGPoint(x: w - r, y: h - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: r, y: h))
        
        // Bottom-left arc
        path.addArc(
            center: CGPoint(x: r, y: h - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        
        // Left side straight up
        path.addLine(to: CGPoint(x: 0, y: neckHeight))
        
        // Left taper: from (0, neckHeight) curving outward to (-flare, 0)
        path.addCurve(
            to: CGPoint(x: -flare, y: 0),
            control1: CGPoint(x: 0, y: neckHeight * ShapeConstants.taperControlInner),
            control2: CGPoint(x: -flare, y: neckHeight * ShapeConstants.taperControlOuter)
        )
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Main View

struct DynamicIslandView: View {
    @ObservedObject var viewModel: DynamicIslandViewModel

    private enum Style {
        static let glowStartOpacity: Double = 0.3
        static let glowEndOpacity: Double = 0.8
        static let glowDuration: Double = 2.5
        static let idleCornerRadius: CGFloat = 16
        static let hoveredCornerRadius: CGFloat = 20
        static let expandedCornerRadius: CGFloat = 22
        static let idleTopFlare: CGFloat = 8
        static let hoveredTopFlare: CGFloat = 12
        static let expandedTopFlare: CGFloat = 16
        static let backgroundTopWhite: CGFloat = 0.14
        static let backgroundBottomWhite: CGFloat = 0.06
        static let borderIdleLineWidth: CGFloat = 0.5
        static let borderActiveLineWidth: CGFloat = 1
        static let shadowIdleRadius: CGFloat = 6
        static let shadowActiveRadius: CGFloat = 14
        static let shadowYOffset: CGFloat = 5
        static let transitionHoveredScale: CGFloat = 0.9
        static let transitionExpandedScale: CGFloat = 0.95
        static let timeTextOpacity: Double = 0.85
        static let buttonContentSpacing: CGFloat = 4
        static let buttonFontSize: CGFloat = 10
        static let buttonTextOpacity: Double = 0.7
        static let buttonHorizontalPadding: CGFloat = 10
        static let buttonVerticalPadding: CGFloat = 5
        static let buttonBackgroundOpacity: Double = 0.1
        static let buttonBorderOpacity: Double = 0.15
        static let quitTextOpacity: Double = 0.7
        static let quitBackgroundOpacity: Double = 0.08
        static let quitBorderOpacity: Double = 0.2
        static let idleBorderOpacity: Double = 0.08
        static let hoveredBorderCyanOpacity: Double = 0.4
        static let hoveredBorderBlueOpacity: Double = 0.3
        static let expandedBorderPurpleOpacity: Double = 0.3
        static let expandedBorderBlueOpacity: Double = 0.2
    }

    
    private var pillWidth: CGFloat {
        viewModel.currentPillSize.width
    }
    
    private var pillHeight: CGFloat {
        viewModel.currentPillSize.height
    }
    
    private var bottomRadius: CGFloat {
        switch viewModel.state {
        case .idle: return Style.idleCornerRadius
        case .hovered: return Style.hoveredCornerRadius
        case .expanded, .settings: return Style.expandedCornerRadius
        }
    }
    
    /// How much the top flares outward on each side
    private var topFlare: CGFloat {
        switch viewModel.state {
        case .idle: return Style.idleTopFlare
        case .hovered: return Style.hoveredTopFlare
        case .expanded, .settings: return Style.expandedTopFlare
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background — Dynamic Island shape
                DynamicIslandShape(bottomRadius: bottomRadius, topFlare: topFlare)
                    .fill(.black)
                    .overlay(
                        DynamicIslandShape(bottomRadius: bottomRadius, topFlare: topFlare)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(white: Style.backgroundTopWhite),
                                        Color(white: Style.backgroundBottomWhite)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        DynamicIslandShape(bottomRadius: bottomRadius, topFlare: topFlare)
                            .stroke(borderGradient, lineWidth: viewModel.state == .idle ? Style.borderIdleLineWidth : Style.borderActiveLineWidth)
                    )
                
                // Content
                contentForState
            }
            .frame(width: pillWidth, height: pillHeight)
            .clipShape(DynamicIslandShape(bottomRadius: bottomRadius, topFlare: topFlare))
            .contentShape(Rectangle())
            .animation(.spring(
                response: viewModel.animationConfig.expandSpringResponse,
                dampingFraction: viewModel.animationConfig.expandSpringDamping
            ), value: viewModel.state)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var contentForState: some View {
        switch viewModel.state {
        case .idle:
            idleContent
                .transition(.opacity)
        case .hovered:
            hoveredContent
                .transition(.opacity.combined(with: .scale(scale: Style.transitionHoveredScale)))
        case .expanded:
            expandedContent
                .transition(.opacity.combined(with: .scale(scale: Style.transitionExpandedScale)))
        case .settings:
            SettingsView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: Style.transitionExpandedScale)))
        }
    }
    
    // MARK: - Idle Content
    
    private var idleContent: some View {
        VStack(spacing: viewModel.idleBarGap) {
            ForEach(viewModel.bars.filter { $0.showInIdle }) { bar in
                TimeBarView(
                    barConfig: bar,
                    progress: viewModel.barProgresses[bar.name] ?? 0,
                    showLabel: false,
                    animationDuration: viewModel.animationConfig.barAnimationDuration,
                    nameSize: viewModel.nameSize,
                    barColor: viewModel.cachedColors[bar.name] ?? .white,
                    timeUnit: viewModel.barUnits[bar.name]
                )
            }
        }
        .padding(.horizontal, viewModel.idlePaddingHorizontal)
        .padding(.top, viewModel.idlePaddingTop)
        .padding(.bottom, viewModel.idlePaddingBottom)
    }
    
    // MARK: - Hovered Content
    
    private var hoveredContent: some View {
        VStack(spacing: viewModel.hoveredContentSpacing) {
            // Current time display
            Text(viewModel.currentTimeString)
                .font(.system(size: viewModel.timeTextSize, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(Style.timeTextOpacity))
                .frame(maxWidth: .infinity, alignment: .center)
            
            ForEach(viewModel.bars.filter { $0.showInExpanded }) { bar in
                TimeBarView(
                    barConfig: bar,
                    progress: viewModel.barProgresses[bar.name] ?? 0,
                    showLabel: true,
                    animationDuration: viewModel.animationConfig.barAnimationDuration,
                    nameSize: viewModel.nameSize,
                    barColor: viewModel.cachedColors[bar.name] ?? .white,
                    timeUnit: viewModel.barUnits[bar.name]
                )
            }
        }
        .padding(.horizontal, viewModel.hoveredPaddingHorizontal)
        .padding(.top, viewModel.hoveredPaddingTop)
        .padding(.bottom, viewModel.hoveredPaddingBottom)
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(spacing: viewModel.expandedContentSpacing) {
            // Current time display
            Text(viewModel.currentTimeString)
                .font(.system(size: viewModel.timeTextSize, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(Style.timeTextOpacity))
                .frame(maxWidth: .infinity, alignment: .center)
            
            ForEach(viewModel.bars.filter { $0.showInExpanded }) { bar in
                TimeBarView(
                    barConfig: bar,
                    progress: viewModel.barProgresses[bar.name] ?? 0,
                    showLabel: true,
                    animationDuration: viewModel.animationConfig.barAnimationDuration,
                    nameSize: viewModel.nameSize,
                    barColor: viewModel.cachedColors[bar.name] ?? .white,
                    timeUnit: viewModel.barUnits[bar.name]
                )
            }
            
            HStack(spacing: viewModel.expandedButtonSpacing) {
                Spacer()
                
                Button(action: {
                    viewModel.transitionTo(.settings)
                }) {
                    HStack(spacing: Style.buttonContentSpacing) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: Style.buttonFontSize))
                        Text("Settings")
                            .font(.system(size: Style.buttonFontSize, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(Style.buttonTextOpacity))
                    .padding(.horizontal, Style.buttonHorizontalPadding)
                    .padding(.vertical, Style.buttonVerticalPadding)
                    .background(Capsule().fill(Color.white.opacity(Style.buttonBackgroundOpacity)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(Style.buttonBorderOpacity), lineWidth: Style.borderIdleLineWidth))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    ConfigManager.shared.load()
                    viewModel.reloadConfig()
                }) {
                    HStack(spacing: Style.buttonContentSpacing) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: Style.buttonFontSize))
                        Text("Reload")
                            .font(.system(size: Style.buttonFontSize, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(Style.buttonTextOpacity))
                    .padding(.horizontal, Style.buttonHorizontalPadding)
                    .padding(.vertical, Style.buttonVerticalPadding)
                    .background(Capsule().fill(Color.white.opacity(Style.buttonBackgroundOpacity)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(Style.buttonBorderOpacity), lineWidth: Style.borderIdleLineWidth))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    HStack(spacing: Style.buttonContentSpacing) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: Style.buttonFontSize))
                        Text("Quit")
                            .font(.system(size: Style.buttonFontSize, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.red.opacity(Style.quitTextOpacity))
                    .padding(.horizontal, Style.buttonHorizontalPadding)
                    .padding(.vertical, Style.buttonVerticalPadding)
                    .background(Capsule().fill(Color.red.opacity(Style.quitBackgroundOpacity)))
                    .overlay(Capsule().strokeBorder(Color.red.opacity(Style.quitBorderOpacity), lineWidth: Style.borderIdleLineWidth))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .padding(.horizontal, viewModel.expandedPaddingHorizontal)
        .padding(.top, viewModel.expandedPaddingTop)
        .padding(.bottom, viewModel.expandedPaddingBottom)
    }
    
    // MARK: - Styling
    
    private var borderGradient: LinearGradient {
        switch viewModel.state {
        case .idle:
            return LinearGradient(
                colors: [.clear, .white.opacity(Style.idleBorderOpacity), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        case .hovered:
            return LinearGradient(
                colors: [.clear, .cyan.opacity(Style.hoveredBorderCyanOpacity), .blue.opacity(Style.hoveredBorderBlueOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .expanded, .settings:
            return LinearGradient(
                colors: [.clear, .purple.opacity(Style.expandedBorderPurpleOpacity), .blue.opacity(Style.expandedBorderBlueOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
}

// MARK: - Root Wrapper View (avoids AnyView type erasure)

struct DynamicIslandRootView: View {
    @ObservedObject var viewModel: DynamicIslandViewModel
    
    var body: some View {
        DynamicIslandView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
