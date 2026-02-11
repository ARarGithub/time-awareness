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
    @Published var state: IslandState = .idle
    @Published var barProgresses: [String: Double] = [:]
    @Published var bars: [BarConfig] = []
    @Published var animationConfig: AnimationConfig = .defaultAnimation
    @Published var barLength: CGFloat = 200
    @Published var barLengthExpanded: CGFloat = 300
    @Published var nameSize: CGFloat = 10
    @Published var timeTextSize: CGFloat = 14
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

    var idleBarGap: CGFloat { 3 }
    var idlePaddingTop: CGFloat { 2 }
    var idlePaddingBottom: CGFloat { 2 }
    var idlePaddingHorizontal: CGFloat { 16 }
    
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
        let barCount = max(visibleBars.count, 1)
        let totalThickness = visibleBars.reduce(CGFloat(0)) { $0 + $1.thickness }
        let gaps = CGFloat(max(barCount - 1, 0)) * idleBarGap
        let height: CGFloat = idlePaddingTop + totalThickness + gaps + idlePaddingBottom
        // Idle width = barLength + horizontal padding (2 * 16)
        let width: CGFloat = barLength + (idlePaddingHorizontal * 2)
        return CGSize(width: max(width, 100), height: max(height, 30))
    }
    
    var hoveredSize: CGSize {
        let visibleBars = expandedBars
        let barCount = max(visibleBars.count, 1)
        let labelHeight: CGFloat = nameSize + 4  // label line height
        let barRowHeight: CGFloat = labelHeight + 3 + max(visibleBars.map({ $0.thickness }).max() ?? 4, 4)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * 4
        let timeHeight: CGFloat = timeTextSize + 6  // time text + spacing
        let height: CGFloat = 16 + timeHeight + barHeight + 16
        let width: CGFloat = barLengthExpanded + 40
        return CGSize(width: max(width, 140), height: max(height, 48))
    }
    
    var expandedSize: CGSize {
        let visibleBars = expandedBars
        let barCount = max(visibleBars.count, 1)
        let labelHeight: CGFloat = nameSize + 4
        let barRowSpacing: CGFloat = 6
        let barRowHeight: CGFloat = labelHeight + 3 + max(visibleBars.map({ $0.thickness }).max() ?? 4, 4)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * barRowSpacing
        let timeHeight: CGFloat = timeTextSize + 8  // time text + spacing below
        let expandedPaddingTop: CGFloat = 14
        let expandedPaddingBottom: CGFloat = 12
        let expandedPaddingHorizontal: CGFloat = 20
        let expandedButtonRowHeight: CGFloat = 36
        let expandedButtonRowSpacing: CGFloat = 12
        let height: CGFloat = expandedPaddingTop + timeHeight + barHeight + expandedPaddingBottom + expandedButtonRowHeight + expandedButtonRowSpacing
        let width: CGFloat = barLengthExpanded + (expandedPaddingHorizontal * 2)
        return CGSize(width: max(width, 200), height: max(height, 80))
    }
    
    var settingsSize: CGSize {
        let width: CGFloat = max(barLengthExpanded + 40, 340)
        return CGSize(width: width, height: 190)
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
            let oldValue = barProgresses[name] ?? -1
            let isSegmented = barConfigMap[name]?.segmented ?? false
            let segments = barConfigMap[name]?.segments ?? 20
            let bucketCount = isSegmented ? segments : 100
            if Int(newValue * Double(bucketCount)) != Int(oldValue * Double(bucketCount)) {
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
                let oldValue = self.barProgresses[name] ?? -1
                let bar = self.barConfigMap[name]
                if bar?.notify == true && oldValue >= 0 {
                    let cycleCompleted = (oldValue - value) > 0.5  // wrap-around detected
                    let reachedFull = value >= 1.0 && oldValue < 1.0
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
                
                // Auto-dismiss after 3 seconds
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.isNotifying = false
                    if self.state == .hovered {
                        self.transitionTo(.idle)
                    }
                }
                self.notificationDismissWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
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
        let neckHeight: CGFloat = min(h * 0.25, 20)
        
        // Top-left corner (extended outward by flare)
        path.move(to: CGPoint(x: -flare, y: 0))
        
        // Top edge — straight, wider than the body
        path.addLine(to: CGPoint(x: w + flare, y: 0))
        
        // Right taper: from (w + flare, 0) curving inward to (w, neckHeight)
        path.addCurve(
            to: CGPoint(x: w, y: neckHeight),
            control1: CGPoint(x: w + flare, y: neckHeight * 0.3),
            control2: CGPoint(x: w, y: neckHeight * 0.5)
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
            control1: CGPoint(x: 0, y: neckHeight * 0.5),
            control2: CGPoint(x: -flare, y: neckHeight * 0.3)
        )
        
        path.closeSubpath()
        return path
    }
}

// MARK: - Main View

struct DynamicIslandView: View {
    @ObservedObject var viewModel: DynamicIslandViewModel
    @State private var glowOpacity: Double = 0.3
    
    private var pillWidth: CGFloat {
        viewModel.currentPillSize.width
    }
    
    private var pillHeight: CGFloat {
        viewModel.currentPillSize.height
    }
    
    private var bottomRadius: CGFloat {
        switch viewModel.state {
        case .idle: return 16
        case .hovered: return 20
        case .expanded, .settings: return 22
        }
    }
    
    /// How much the top flares outward on each side
    private var topFlare: CGFloat {
        switch viewModel.state {
        case .idle: return 8
        case .hovered: return 12
        case .expanded, .settings: return 16
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
                                        Color(white: 0.14),
                                        Color(white: 0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        DynamicIslandShape(bottomRadius: bottomRadius, topFlare: topFlare)
                            .stroke(borderGradient, lineWidth: viewModel.state == .idle ? 0.5 : 1)
                    )
                    .shadow(color: shadowColor, radius: viewModel.state == .idle ? 6 : 14, y: 5)
                
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
        .onAppear {
            if viewModel.animationConfig.idleGlow {
                startIdleGlow()
            }
        }
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
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .expanded:
            expandedContent
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .settings:
            SettingsView(viewModel: viewModel)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
    
    // MARK: - Idle Content
    
    private var idleContent: some View {
        VStack(spacing: 3) {
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
        VStack(spacing: 4) {
            // Current time display
            Text(viewModel.currentTimeString)
                .font(.system(size: viewModel.timeTextSize, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
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
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(spacing: 6) {
            // Current time display
            Text(viewModel.currentTimeString)
                .font(.system(size: viewModel.timeTextSize, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
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
            
            HStack(spacing: 12) {
                Spacer()
                
                Button(action: {
                    viewModel.transitionTo(.settings)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10))
                        Text("Settings")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    ConfigManager.shared.load()
                    viewModel.reloadConfig()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Reload")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    NSApp.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Quit")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.red.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.red.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
    
    // MARK: - Styling
    
    private var borderGradient: LinearGradient {
        switch viewModel.state {
        case .idle:
            return LinearGradient(
                colors: [.clear, .white.opacity(0.06 + glowOpacity * 0.04), .white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .hovered:
            return LinearGradient(
                colors: [.clear, .cyan.opacity(0.4), .blue.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .expanded, .settings:
            return LinearGradient(
                colors: [.clear, .purple.opacity(0.3), .blue.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var shadowColor: Color {
        switch viewModel.state {
        case .idle: return .black.opacity(0.4)
        case .hovered: return .cyan.opacity(0.2)
        case .expanded, .settings: return .purple.opacity(0.15)
        }
    }
    
    // MARK: - Animations
    
    private func startIdleGlow() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            glowOpacity = 0.8
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
