import SwiftUI

/// Individual progress bar with configurable color, thickness, and rounded caps.
/// Supports two rendering modes: continuous (default) and segmented (block-style).
struct TimeBarView: View {
    let barConfig: BarConfig
    let progress: Double
    let showLabel: Bool
    let animationDuration: Double
    let nameSize: CGFloat
    /// Pre-parsed color to avoid repeated ColorParser.parse() calls per body evaluation
    let barColor: Color
    /// The time unit of this bar's rule, used to adapt animation curve
    let timeUnit: TimeRule.Unit?
    
    @State private var animatedProgress: Double = 0
    
    /// Adapt animation to the bar's time unit:
    /// - seconds: short linear animation to avoid perpetual catch-up
    /// - others: easeInOut with configured duration
    private var progressAnimation: Animation {
        if timeUnit == .seconds {
            return .linear(duration: min(animationDuration, 0.3))
        }
        return .easeInOut(duration: animationDuration)
    }

    private var displayProgress: Double {
        ceilingProgress(animatedProgress)
    }

    
    var body: some View {
        VStack(alignment: .leading, spacing: showLabel ? 3 : 0) {
            if showLabel {
                HStack {
                    Text(barConfig.name)
                        .font(.system(size: nameSize, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("\(Int(animatedProgress * 100))%")
                        .font(.system(size: nameSize, weight: .bold, design: .monospaced))
                        .foregroundColor(barColor.opacity(0.9))
                }
            }
            
            if barConfig.segmented {
                segmentedBar
            } else {
                continuousBar
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(progressAnimation) {
                animatedProgress = newValue
            }
        }
        .onAppear {
            animatedProgress = progress
        }
    }
    
    // MARK: - Continuous Bar (default)
    
    private var continuousBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: barConfig.thickness)
                
                // Filled portion
                Capsule()
                    .fill(barColor)
                    .frame(width: max(barConfig.thickness, geo.size.width * displayProgress), height: barConfig.thickness)
            }
        }
        .frame(height: barConfig.thickness)
    }
    
    // MARK: - Segmented Bar
    
    private var segmentedBar: some View {
        EquatableView(content: SegmentedBarView(
            segments: barConfig.segments,
            thickness: barConfig.thickness,
            filledCount: segmentedStepCount(animatedProgress),
            barColor: barColor,
            colorKey: barConfig.color
        ))
    }

    private struct SegmentedBarView: View, Equatable {
        let segments: Int
        let thickness: CGFloat
        let filledCount: Int
        let barColor: Color
        let colorKey: String

        static func == (lhs: SegmentedBarView, rhs: SegmentedBarView) -> Bool {
            lhs.segments == rhs.segments &&
            lhs.thickness == rhs.thickness &&
            lhs.filledCount == rhs.filledCount &&
            lhs.colorKey == rhs.colorKey
        }

        var body: some View {
            GeometryReader { geo in
                let gap: CGFloat = 1.5
                let totalGaps = CGFloat(segments - 1) * gap
                let segWidth = (geo.size.width - totalGaps) / CGFloat(segments)

                HStack(spacing: gap) {
                    ForEach(0..<segments, id: \.self) { i in
                        let isFilled = i < filledCount
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isFilled ? barColor : Color.white.opacity(0.06))
                            .frame(width: segWidth, height: thickness)
                    }
                }
            }
            .frame(height: thickness)
        }
    }

    private func ceilingProgress(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        // Dead code for now.
        if barConfig.segmented {
            let steps = segmentedStepCount(clamped)
            let segments = Double(max(1, barConfig.segments))
            return Double(steps) / segments
        }
        let step = 0.01
        let ceiled = ceil(clamped / step) * step
        return min(max(ceiled, 0), 1)
    }

    private func segmentedStepCount(_ value: Double) -> Int {
        let segments = max(1, barConfig.segments)
        let clamped = min(max(value, 0), 1)
        let rawSteps = clamped * Double(segments)
        let steps = Int((rawSteps - 1e-9).rounded(.up))
        return min(max(steps, 0), segments)
    }
}
