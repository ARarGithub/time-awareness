import SwiftUI

/// Parses hex color strings like "#RRGGBB" or "#RRGGBBAA" into SwiftUI Color.
struct ColorParser {
    
    /// Parse a hex color string. Supports:
    ///   "#RRGGBB"   → opaque
    ///   "#RRGGBBAA" → with alpha
    static func parse(_ hex: String) -> Color {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") {
            str.removeFirst()
        }
        
        var rgba: UInt64 = 0
        Scanner(string: str).scanHexInt64(&rgba)
        
        let r, g, b, a: Double
        
        switch str.count {
        case 6: // RRGGBB
            r = Double((rgba >> 16) & 0xFF) / 255
            g = Double((rgba >> 8) & 0xFF) / 255
            b = Double(rgba & 0xFF) / 255
            a = 1.0
            
        case 8: // RRGGBBAA
            r = Double((rgba >> 24) & 0xFF) / 255
            g = Double((rgba >> 16) & 0xFF) / 255
            b = Double((rgba >> 8) & 0xFF) / 255
            a = Double(rgba & 0xFF) / 255
            
        default:
            return .white
        }
        
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
    
    /// Convert a Color back to hex string (#RRGGBBAA)
    static func toHex(_ color: Color) -> String {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.white
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        let a = Int(nsColor.alphaComponent * 255)
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
