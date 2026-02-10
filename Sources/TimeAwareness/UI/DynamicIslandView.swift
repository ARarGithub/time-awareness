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
    @Published var nameSize: CGFloat = 10
    @Published var timeTextSize: CGFloat = 14
    @Published var timeFormat: String = "24h"
    @Published var timeShowSeconds: Bool = true
    @Published var currentTimeString: String = ""
    
    /// Pre-parsed colors keyed by bar name — avoids repeated ColorParser.parse() in view body
    private(set) var cachedColors: [String: Color] = [:]
    /// Time units keyed by bar name — used to adapt animation curves
    private(set) var barUnits: [String: TimeRule.Unit] = [:]
    
    private var timer: Timer?
    private var rules: [String: TimeRule] = [:]
    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    init() {
        reloadConfig()
        startTimer()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func reloadConfig() {
        let config = ConfigManager.shared.config
        bars = config.bars
        animationConfig = config.animation
        barLength = config.barLength
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
        for bar in config.bars {
            cachedColors[bar.name] = ColorParser.parse(bar.color)
            if let rule = TimeRule.parse(bar.rule) {
                rules[bar.name] = rule
                barUnits[bar.name] = rule.unit
            }
        }
        
        // Immediately update progress
        updateProgress()
    }
    
    func transitionTo(_ newState: IslandState) {
        withAnimation(.spring(
            response: animationConfig.expandSpringResponse,
            dampingFraction: animationConfig.expandSpringDamping
        )) {
            state = newState
        }
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
        let barCount = max(bars.count, 1)
        let totalThickness = bars.reduce(CGFloat(0)) { $0 + $1.thickness }
        let gaps = CGFloat(max(barCount - 1, 0)) * 3
        let height: CGFloat = 10 + totalThickness + gaps + 10
        // Idle width = barLength + horizontal padding (32)
        let width: CGFloat = barLength + 32
        return CGSize(width: max(width, 100), height: max(height, 30))
    }
    
    var hoveredSize: CGSize {
        let barCount = max(bars.count, 1)
        let labelHeight: CGFloat = nameSize + 4  // label line height
        let barRowHeight: CGFloat = labelHeight + 3 + max(bars.map({ $0.thickness }).max() ?? 4, 4)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * 4
        let timeHeight: CGFloat = timeTextSize + 6  // time text + spacing
        let height: CGFloat = 16 + timeHeight + barHeight + 16
        let width: CGFloat = barLength + 40
        return CGSize(width: max(width, 140), height: max(height, 48))
    }
    
    var expandedSize: CGSize {
        let barCount = max(bars.count, 1)
        let labelHeight: CGFloat = nameSize + 4
        let barRowHeight: CGFloat = labelHeight + 3 + max(bars.map({ $0.thickness }).max() ?? 4, 4)
        let barHeight: CGFloat = CGFloat(barCount) * barRowHeight + CGFloat(barCount - 1) * 6
        let timeHeight: CGFloat = timeTextSize + 8  // time text + spacing below
        let height: CGFloat = 16 + timeHeight + barHeight + 16 + 36 + 12
        let width: CGFloat = barLength + 40
        return CGSize(width: max(width, 200), height: max(height, 80))
    }
    
    var settingsSize: CGSize {
        let barCount = max(bars.count, 1)
        let editorRowHeight: CGFloat = 24
        let barsHeight: CGFloat = CGFloat(barCount) * editorRowHeight + CGFloat(barCount - 1) * 6
        let height: CGFloat = 30 + min(barsHeight + 30, 170) + 40 + 16
        let width: CGFloat = max(barLength + 40, 380)
        return CGSize(width: width, height: max(height, 140))
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        let now = Date()
        
        // Update current time string
        let newTimeString = timeFormatter.string(from: now)
        
        // Per-bar diffing: only update bars whose displayed value actually changed.
        // Segmented bars use 20-bucket granularity (5%), continuous bars use 100-bucket (1%).
        // This prevents a continuous bar's updates from forcing a segmented bar to re-render.
        var updates: [String: Double] = [:]
        for (name, rule) in rules {
            let newValue = rule.progress(at: now)
            let oldValue = barProgresses[name] ?? -1
            let isSegmented = bars.first(where: { $0.name == name })?.segmented ?? false
            let granularity = isSegmented ? 20 : 100
            if Int(newValue * Double(granularity)) != Int(oldValue * Double(granularity)) {
                updates[name] = newValue
            }
        }
        
        let timeChanged = newTimeString != currentTimeString
        guard !updates.isEmpty || timeChanged else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if timeChanged {
                self.currentTimeString = newTimeString
            }
            for (name, value) in updates {
                self.barProgresses[name] = value
            }
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
            ForEach(viewModel.bars) { bar in
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
    
    // MARK: - Hovered Content
    
    private var hoveredContent: some View {
        VStack(spacing: 4) {
            // Current time display
            Text(viewModel.currentTimeString)
                .font(.system(size: viewModel.timeTextSize, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .center)
            
            ForEach(viewModel.bars) { bar in
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
            
            ForEach(viewModel.bars) { bar in
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
