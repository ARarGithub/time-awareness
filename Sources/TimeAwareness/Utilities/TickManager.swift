import Foundation

enum TickGranularity: Int, CaseIterable {
    case second
    case minute
    case hour
    case day
}

final class TickManager {
    typealias TickHandler = (_ date: Date, _ changed: Set<TickGranularity>) -> Void

    private var timer: Timer?
    private var registrations: [TickGranularity: Set<String>] = {
        var map: [TickGranularity: Set<String>] = [:]
        for granularity in TickGranularity.allCases {
            map[granularity] = []
        }
        return map
    }()

    private var lastSecond: Int?
    private var lastMinute: Int?
    private var lastHour: Int?
    private var lastDayOfYear: Int?

    var onTick: TickHandler?

    deinit {
        timer?.invalidate()
    }

    func setRegistrations(_ newRegistrations: [String: TickGranularity]) {
        for key in registrations.keys {
            registrations[key]?.removeAll()
        }
        for (name, granularity) in newRegistrations {
            registrations[granularity, default: []].insert(name)
        }
        rescheduleTimer()
    }

    func registeredNames(for granularity: TickGranularity) -> Set<String> {
        registrations[granularity] ?? []
    }

    private func rescheduleTimer() {
        timer?.invalidate()
        timer = nil

        let activeGranularities = registrations
            .filter { !$0.value.isEmpty }
            .map { $0.key }

        guard let smallest = activeGranularities.min(by: { $0.rawValue < $1.rawValue }) else {
            return
        }

        let now = Date()
        updateLastComponents(now)

        let nextFire = nextFireDate(for: smallest, from: now)
        let interval = intervalSeconds(for: smallest)

        let newTimer = Timer(fireAt: nextFire, interval: interval, target: self, selector: #selector(handleTick), userInfo: nil, repeats: true)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    @objc private func handleTick() {
        let now = Date()
        let calendar = Calendar.current
        var changed: Set<TickGranularity> = []

        if !(registrations[.second]?.isEmpty ?? true) {
            let second = calendar.component(.second, from: now)
            if second != lastSecond {
                lastSecond = second
                changed.insert(.second)
            }
        }

        if !(registrations[.minute]?.isEmpty ?? true) {
            let minute = calendar.component(.minute, from: now)
            if minute != lastMinute {
                lastMinute = minute
                changed.insert(.minute)
            }
        }

        if !(registrations[.hour]?.isEmpty ?? true) {
            let hour = calendar.component(.hour, from: now)
            if hour != lastHour {
                lastHour = hour
                changed.insert(.hour)
            }
        }

        if !(registrations[.day]?.isEmpty ?? true) {
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
            if dayOfYear != lastDayOfYear {
                lastDayOfYear = dayOfYear
                changed.insert(.day)
            }
        }

        guard !changed.isEmpty else { return }
        onTick?(now, changed)
    }

    private func updateLastComponents(_ now: Date) {
        let calendar = Calendar.current
        lastSecond = calendar.component(.second, from: now)
        lastMinute = calendar.component(.minute, from: now)
        lastHour = calendar.component(.hour, from: now)
        lastDayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
    }

    private func nextFireDate(for granularity: TickGranularity, from now: Date) -> Date {
        let calendar = Calendar.current
        switch granularity {
        case .second:
            let next = floor(now.timeIntervalSince1970) + 1
            return Date(timeIntervalSince1970: next)
        case .minute:
            let start = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            return calendar.date(byAdding: .minute, value: 1, to: start) ?? now.addingTimeInterval(60)
        case .hour:
            let start = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            return calendar.date(byAdding: .hour, value: 1, to: start) ?? now.addingTimeInterval(3600)
        case .day:
            let start = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86400)
        }
    }

    private func intervalSeconds(for granularity: TickGranularity) -> TimeInterval {
        switch granularity {
        case .second: return 1
        case .minute: return 60
        case .hour: return 3600
        case .day: return 86400
        }
    }
}
