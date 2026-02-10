import Foundation

/// Parses rule strings like "60s", "60m", "24h", "16h 8h" and computes progress.
struct TimeRule {
    enum Unit {
        case seconds
        case minutes
        case hours
    }
    
    let totalDuration: Double  // in seconds
    let offset: Double         // in seconds from midnight
    let unit: Unit
    
    /// Parse a rule string.
    /// Formats:
    ///   "60s"    → 60-second cycle (resets every minute)
    ///   "60m"    → 60-minute cycle (resets every hour)
    ///   "24h"    → 24-hour cycle from midnight
    ///   "16h 8h" → 16-hour duration, starting at 8h from midnight
    static func parse(_ rule: String) -> TimeRule? {
        let parts = rule.trimmingCharacters(in: .whitespaces).split(separator: " ")
        
        guard let first = parts.first else { return nil }
        
        // Parse the main duration
        guard let (dur, unit) = parsePart(String(first)) else { return nil }
        
        // Parse optional offset
        var offsetSeconds: Double = 0
        if parts.count >= 2 {
            if let (off, _) = parsePart(String(parts[1])) {
                offsetSeconds = off
            }
        }
        
        return TimeRule(totalDuration: dur, offset: offsetSeconds, unit: unit)
    }
    
    /// Parse a single value+unit like "60s", "60m", "16h"
    private static func parsePart(_ s: String) -> (Double, Unit)? {
        let str = s.lowercased().trimmingCharacters(in: .whitespaces)
        
        if str.hasSuffix("s") {
            if let val = Double(str.dropLast()) {
                return (val, .seconds)  // already in seconds
            }
        } else if str.hasSuffix("m") {
            if let val = Double(str.dropLast()) {
                return (val * 60, .minutes)
            }
        } else if str.hasSuffix("h") {
            if let val = Double(str.dropLast()) {
                return (val * 3600, .hours)
            }
        }
        
        return nil
    }
    
    /// Returns progress 0.0–1.0 for the given date.
    func progress(at date: Date = Date()) -> Double {
        let calendar = Calendar.current
        
        switch unit {
        case .seconds:
            // Cycle within the current minute
            let second = calendar.component(.second, from: date)
            let nanosecond = calendar.component(.nanosecond, from: date)
            let currentSec = Double(second) + Double(nanosecond) / 1_000_000_000
            let p = currentSec.truncatingRemainder(dividingBy: totalDuration) / totalDuration
            return min(max(p, 0), 1)
            
        case .minutes:
            // Cycle within the current hour
            let minute = calendar.component(.minute, from: date)
            let second = calendar.component(.second, from: date)
            let currentSec = Double(minute) * 60 + Double(second)
            let p = currentSec.truncatingRemainder(dividingBy: totalDuration) / totalDuration
            return min(max(p, 0), 1)
            
        case .hours:
            // Seconds since midnight
            let startOfDay = calendar.startOfDay(for: date)
            let elapsed = date.timeIntervalSince(startOfDay)
            
            // Apply offset
            let adjusted = elapsed - offset
            
            if adjusted < 0 {
                return 0
            }
            
            let p = adjusted / totalDuration
            return min(max(p, 0), 1)
        }
    }
}
