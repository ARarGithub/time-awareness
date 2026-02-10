import SwiftUI

/// Individual progress bar with configurable color, thickness, and rounded caps.
struct TimeBarView: View {
    let barConfig: BarConfig
    let progress: Double
    let showLabel: Bool
    let animationDuration: Double
    let nameSize: CGFloat
    
    @State private var animatedProgress: Double = 0
    @State private var glowPulse: Bool = false
    
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
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: barConfig.thickness)
                    
                    // Filled portion — preserve parsed alpha from hex color
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    barColor,
                                    barColor
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(barConfig.thickness, geo.size.width * animatedProgress), height: barConfig.thickness)
                        .shadow(color: barColor, radius: glowPulse ? 8 : 2)
                }
            }
            .frame(height: barConfig.thickness)
        }
        .onChange(of: progress) { newValue in
            withAnimation(.easeInOut(duration: animationDuration)) {
                animatedProgress = newValue
            }
            checkThresholdGlow(newValue)
        }
        .onAppear {
            animatedProgress = progress
        }
    }
    
    private var barColor: Color {
        ColorParser.parse(barConfig.color)
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
