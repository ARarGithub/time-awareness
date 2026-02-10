import Foundation

/// Parses rule strings like "60s", "60m", "24h", "16h 8h", "year", "month", "week" and computes progress.
struct TimeRule {
    enum Unit {
        case seconds
        case minutes
        case hours
        case days
        case week
        case month
        case year
    }
    
    let totalDuration: Double  // in seconds (for s/m/h), or number of days (for d)
    let offset: Double         // in seconds from midnight (for h rules)
    let unit: Unit
    
    /// Whether this rule only changes once per day (days/week/month/year)
    var isDayBased: Bool {
        switch unit {
        case .days, .week, .month, .year: return true
        case .seconds, .minutes, .hours: return false
        }
    }
    
    /// Parse a rule string.
    /// Formats:
    ///   "60s"    → 60-second cycle (resets every minute)
    ///   "60m"    → 60-minute cycle (resets every hour)
    ///   "24h"    → 24-hour cycle from midnight
    ///   "16h 8h" → 16-hour duration, starting at 8h from midnight
    ///   "365d"   → day-of-year / 365
    ///   "year"   → day-of-year / days-in-current-year (auto leap year)
    ///   "month"  → day-of-month / days-in-current-month
    ///   "week"   → day-of-week / 7 (Monday = 1)
    static func parse(_ rule: String) -> TimeRule? {
        let trimmed = rule.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Named rules
        switch trimmed {
        case "year":
            return TimeRule(totalDuration: 0, offset: 0, unit: .year)
        case "month":
            return TimeRule(totalDuration: 0, offset: 0, unit: .month)
        case "week":
            return TimeRule(totalDuration: 7, offset: 0, unit: .week)
        default:
            break
        }
        
        let parts = trimmed.split(separator: " ")
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
                return (val, .seconds)
            }
        } else if str.hasSuffix("m") {
            if let val = Double(str.dropLast()) {
                return (val * 60, .minutes)
            }
        } else if str.hasSuffix("h") {
            if let val = Double(str.dropLast()) {
                return (val * 3600, .hours)
            }
        } else if str.hasSuffix("d") {
            if let val = Double(str.dropLast()) {
                return (val, .days)
            }
        }
        
        return nil
    }
    
    /// Returns progress 0.0–1.0 for the given date.
    func progress(at date: Date = Date()) -> Double {
        let calendar = Calendar.current
        
        switch unit {
        case .seconds:
            let second = calendar.component(.second, from: date)
            let nanosecond = calendar.component(.nanosecond, from: date)
            let currentSec = Double(second) + Double(nanosecond) / 1_000_000_000
            let p = currentSec.truncatingRemainder(dividingBy: totalDuration) / totalDuration
            return min(max(p, 0), 1)
            
        case .minutes:
            let minute = calendar.component(.minute, from: date)
            let second = calendar.component(.second, from: date)
            let currentSec = Double(minute) * 60 + Double(second)
            let p = currentSec.truncatingRemainder(dividingBy: totalDuration) / totalDuration
            return min(max(p, 0), 1)
            
        case .hours:
            let startOfDay = calendar.startOfDay(for: date)
            let elapsed = date.timeIntervalSince(startOfDay)
            let adjusted = elapsed - offset
            if adjusted < 0 { return 0 }
            let p = adjusted / totalDuration
            return min(max(p, 0), 1)
            
        case .days:
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            let p = Double(dayOfYear) / totalDuration
            return min(max(p, 0), 1)
            
        case .year:
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
            let p = Double(dayOfYear) / Double(daysInYear)
            return min(max(p, 0), 1)
            
        case .month:
            let dayOfMonth = calendar.component(.day, from: date)
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            let p = Double(dayOfMonth) / Double(daysInMonth)
            return min(max(p, 0), 1)
            
        case .week:
            // ISO weekday: Monday=2 in Calendar, we want Monday=1
            let weekday = calendar.component(.weekday, from: date)
            // Convert: Sun=1 → 7, Mon=2 → 1, Tue=3 → 2, ...
            let dayOfWeek = weekday == 1 ? 7 : weekday - 1
            let p = Double(dayOfWeek) / 7.0
            return min(max(p, 0), 1)
        }
    }
}
