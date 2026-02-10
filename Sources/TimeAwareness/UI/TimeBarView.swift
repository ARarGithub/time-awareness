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
    @State private var glowPulse: Bool = false
    
    /// Number of discrete segments for segmented bars
    private let segmentCount = 20
    
    /// Adapt animation to the bar's time unit:
    /// - seconds: short linear animation to avoid perpetual catch-up
    /// - others: easeInOut with configured duration
    private var progressAnimation: Animation {
        if timeUnit == .seconds {
            return .linear(duration: min(animationDuration, 0.3))
        }
        return .easeInOut(duration: animationDuration)
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
            checkThresholdGlow(newValue)
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
                    .frame(width: max(barConfig.thickness, geo.size.width * animatedProgress), height: barConfig.thickness)
                    .shadow(color: barColor, radius: glowPulse ? 8 : 2)
            }
        }
        .frame(height: barConfig.thickness)
    }
    
    // MARK: - Segmented Bar
    
    private var segmentedBar: some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            let totalGaps = CGFloat(segmentCount - 1) * gap
            let segWidth = (geo.size.width - totalGaps) / CGFloat(segmentCount)
            let filledCount = Int(round(animatedProgress * Double(segmentCount)))
            
            HStack(spacing: gap) {
                ForEach(0..<segmentCount, id: \.self) { i in
                    let isFilled = i < filledCount
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isFilled ? barColor : Color.white.opacity(0.06))
                        .frame(width: segWidth, height: barConfig.thickness)
                        .shadow(color: isFilled ? barColor.opacity(glowPulse ? 0.6 : 0.2) : .clear, radius: isFilled ? 3 : 0)
                }
            }
        }
        .frame(height: barConfig.thickness)
    }
    
    /// Flash glow when crossing 25/50/75/100 thresholds
    private func checkThresholdGlow(_ newProgress: Double) {
        let thresholds: [Double] = [0.25, 0.5, 0.75, 1.0]
        let oldBucket = thresholds.filter { $0 <= animatedProgress }.count
        let newBucket = thresholds.filter { $0 <= newProgress }.count
        
        if newBucket != oldBucket {
            withAnimation(.easeInOut(duration: 0.3)) {
                glowPulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    glowPulse = false
                }
            }
        }
    }
}
