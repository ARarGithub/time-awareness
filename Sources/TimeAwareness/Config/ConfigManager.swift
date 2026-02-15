import Foundation
import Yams

/// Manages reading and writing the YAML configuration file
class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/time_awareness")
    }()
    
    private var configFileURL: URL {
        configDir.appendingPathComponent("config.yaml")
    }
    
    private(set) var config: AppConfig = AppConfig.defaultConfig
    
    private init() {}
    
    // MARK: - Public API
    
    /// Ensures the config directory and default config file exist
    func ensureDefaultConfig() {
        let fm = FileManager.default
        
        // Create directory
        if !fm.fileExists(atPath: configDir.path) {
            do {
                try fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            } catch {
                print("[ConfigManager] Failed to create config directory: \(error)")
            }
        }
        
        // Create default config if not present
        if !fm.fileExists(atPath: configFileURL.path) {
            let defaultYAML = AppConfig.defaultYAML
            do {
                try defaultYAML.write(to: configFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("[ConfigManager] Failed to write default config: \(error)")
            }
        }
    }
    
    /// Load (or reload) the config from disk
    func load() {
        let path = configFileURL.path
        
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let yamlString = String(data: data, encoding: .utf8) else {
            print("[ConfigManager] Config file not found or unreadable at: \(path). Using defaults.")
            config = AppConfig.defaultConfig
            return
        }
        
        print("[ConfigManager] Loaded config from disk (\(data.count) bytes): \(path)")
        
        do {
            config = try AppConfig.from(yaml: yamlString)
            print("[ConfigManager] Parsed \(config.bars.count) bars: \(config.bars.map { "\($0.name) (thk=\($0.thickness))" })")
        } catch {
            print("[ConfigManager] Failed to parse config: \(error). Using defaults.")
            config = AppConfig.defaultConfig
        }
        
        NotificationCenter.default.post(name: .configDidReload, object: nil)
    }
    
    /// Save the current config to disk
    func save(_ newConfig: AppConfig) {
        var normalized = newConfig
        normalized.bars = makeBarNamesUnique(normalized.bars)
        config = normalized
        let yamlString = normalized.toYAML()
        do {
            try yamlString.write(to: configFileURL, atomically: true, encoding: .utf8)
        } catch {
            print("[ConfigManager] Failed to save config: \(error)")
        }
        NotificationCenter.default.post(name: .configDidReload, object: nil)
    }
    
    /// Returns the path of the config file
    var configFilePath: String {
        configFileURL.path
    }

    private func makeBarNamesUnique(_ bars: [BarConfig]) -> [BarConfig] {
        var seenNames: Set<String> = []

        return bars.map { bar in
            var updated = bar
            let trimmed = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseName = trimmed.isEmpty ? "bar" : trimmed

            if !seenNames.contains(baseName) {
                updated.name = baseName
                seenNames.insert(baseName)
                return updated
            }

            var suffix = 1
            var candidate = "\(baseName)_\(suffix)"
            while seenNames.contains(candidate) {
                suffix += 1
                candidate = "\(baseName)_\(suffix)"
            }
            updated.name = candidate
            seenNames.insert(candidate)
            return updated
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let configDidReload = Notification.Name("configDidReload")
}

// MARK: - Helpers

private func nodeValue(for key: String, in mapping: Node.Mapping) -> Node? {
    mapping.first(where: { $0.key == Node(key) })?.value
}

private func nodeCGFloat(_ node: Node?) -> CGFloat? {
    if let d = node?.float { return CGFloat(d) }
    if let i = node?.int { return CGFloat(i) }
    return nil
}

private func nodeDouble(_ node: Node?) -> Double? {
    if let d = node?.float { return d }
    if let i = node?.int { return Double(i) }
    return nil
}

// MARK: - Centralized Defaults

/// Single source of truth for all default values.
/// Change a value here and it propagates everywhere.
enum Defaults {
    // Bar
    static let barRule = "minute"
    static let barColor = "#80C4FFCC"
    static let barThickness: CGFloat = 3
    static let barSegmented = false
    static let barSegments = 20
    static let barNotify = false
    static let barShowInIdle = true
    static let barShowInExpanded = true
    
    // Display
    static let barLength: CGFloat = 300
    static let barLengthExpanded: CGFloat = 400
    static let nameSize: CGFloat = 20
    static let timeTextSize: CGFloat = 24
    static let timeFormat = "24h"
    static let timeShowSeconds = true
    
    // Animation
    static let expandSpringResponse = 0.45
    static let expandSpringDamping = 0.68
    static let barAnimationDuration = 1.0
}

// MARK: - Data Models

struct BarConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var rule: String
    var color: String
    var thickness: CGFloat
    /// When true, renders as discrete segments instead of a continuous bar
    var segmented: Bool
    /// Number of segments when segmented mode is enabled
    var segments: Int
    /// When true, auto-expands to hovered state when bar reaches 100%
    var notify: Bool
    /// Show this bar in the idle (compact) state
    var showInIdle: Bool
    /// Show this bar in the hovered/expanded states
    var showInExpanded: Bool
    
    static func defaultBars() -> [BarConfig] {
        [
            BarConfig(name: "Year",    rule: "year",    color: "#B39DDBCC", thickness: Defaults.barThickness, segmented: false, segments: Defaults.barSegments, notify: false, showInIdle: true, showInExpanded: true),
            BarConfig(name: "Month",   rule: "month",   color: "#80CBC4CC", thickness: Defaults.barThickness, segmented: false, segments: Defaults.barSegments, notify: false, showInIdle: true, showInExpanded: true),
            BarConfig(name: "Week",    rule: "week",    color: "#A5D6A7CC", thickness: Defaults.barThickness, segmented: true,  segments: 7, notify: false, showInIdle: true, showInExpanded: true),
            BarConfig(name: "Day",     rule: "16h 8h",  color: "#FF80ABCC", thickness: Defaults.barThickness, segmented: false, segments: Defaults.barSegments, notify: false, showInIdle: true, showInExpanded: true),
            BarConfig(name: "Hour", rule: "hour",   color: "#FFD580CC", thickness: Defaults.barThickness, segmented: false, segments: Defaults.barSegments, notify: false, showInIdle: true, showInExpanded: true),
            BarConfig(name: "Minute", rule: "minute", color: "#80C4FFCC", thickness: Defaults.barThickness, segmented: false, segments: Defaults.barSegments, notify: false, showInIdle: true, showInExpanded: true),
        ]
    }
}

struct AnimationConfig: Codable, Equatable {
    var expandSpringResponse: Double
    var expandSpringDamping: Double
    var barAnimationDuration: Double
    
    static let defaultAnimation = AnimationConfig(
        expandSpringResponse: Defaults.expandSpringResponse,
        expandSpringDamping: Defaults.expandSpringDamping,
        barAnimationDuration: Defaults.barAnimationDuration
    )
    
    enum CodingKeys: String, CodingKey {
        case expandSpringResponse = "expand_spring_response"
        case expandSpringDamping = "expand_spring_damping"
        case barAnimationDuration = "bar_animation_duration"
    }
}

struct AppConfig: Equatable {
    var bars: [BarConfig]
    var animation: AnimationConfig
    /// Width of progress bars in idle state (compact)
    var barLength: CGFloat
    /// Width of progress bars in hovered/expanded states
    var barLengthExpanded: CGFloat
    /// Font size of bar names in the expanded view (determines row height)
    var nameSize: CGFloat
    /// Font size of the current-time text shown in the expanded view
    var timeTextSize: CGFloat
    /// Time display format: "12h" or "24h"
    var timeFormat: String
    /// Whether to show seconds in the time display
    var timeShowSeconds: Bool
    
    static let defaultConfig = AppConfig(
        bars: BarConfig.defaultBars(),
        animation: .defaultAnimation,
        barLength: Defaults.barLength,
        barLengthExpanded: Defaults.barLengthExpanded,
        nameSize: Defaults.nameSize,
        timeTextSize: Defaults.timeTextSize,
        timeFormat: Defaults.timeFormat,
        timeShowSeconds: Defaults.timeShowSeconds
    )
    
    /// Generate defaultYAML from the default config (so it stays in sync)
    static var defaultYAML: String {
        defaultConfig.toYAML()
    }
    
    // MARK: - YAML Parsing
    
    static func from(yaml: String) throws -> AppConfig {
        guard let node = try Yams.compose(yaml: yaml),
              case .mapping(let rootMapping) = node else {
            return .defaultConfig
        }
        
        // Parse bars — use Yams Node API to preserve user-defined ordering
        var bars: [BarConfig] = []
        if let barsNode = nodeValue(for: "bars", in: rootMapping),
           case .mapping(let barsMapping) = barsNode {
            for (keyNode, valueNode) in barsMapping {
                guard let name = keyNode.string else { continue }
                if case .mapping(let barMapping) = valueNode {
                    let rule = nodeValue(for: "rule", in: barMapping)?.string ?? Defaults.barRule
                    let color = nodeValue(for: "color", in: barMapping)?.string ?? Defaults.barColor
                    let thickness = nodeCGFloat(nodeValue(for: "thickness", in: barMapping)) ?? Defaults.barThickness
                    let segmented = nodeValue(for: "segmented", in: barMapping)?.bool ?? Defaults.barSegmented
                    let segmentsVal = nodeValue(for: "segments", in: barMapping)
                    let segments = segmentsVal?.int ?? Defaults.barSegments
                    let notify = nodeValue(for: "notify", in: barMapping)?.bool ?? Defaults.barNotify
                    let showInIdle = nodeValue(for: "show_in_idle", in: barMapping)?.bool ?? Defaults.barShowInIdle
                    let showInExpanded = nodeValue(for: "show_in_expanded", in: barMapping)?.bool ?? Defaults.barShowInExpanded
                    bars.append(BarConfig(name: name, rule: rule, color: color, thickness: thickness, segmented: segmented, segments: segments, notify: notify, showInIdle: showInIdle, showInExpanded: showInExpanded))
                } else {
                    bars.append(BarConfig(name: name, rule: Defaults.barRule, color: Defaults.barColor, thickness: Defaults.barThickness, segmented: Defaults.barSegmented, segments: Defaults.barSegments, notify: Defaults.barNotify, showInIdle: Defaults.barShowInIdle, showInExpanded: Defaults.barShowInExpanded))
                }
            }
        }
        
        if bars.isEmpty {
            bars = BarConfig.defaultBars()
        }
        
        // Parse animation
        var animation = AnimationConfig.defaultAnimation
        if let animNode = nodeValue(for: "animation", in: rootMapping),
           case .mapping(let animMapping) = animNode {
            if let resp = nodeDouble(nodeValue(for: "expand_spring_response", in: animMapping)) {
                animation.expandSpringResponse = resp
            }
            if let damp = nodeDouble(nodeValue(for: "expand_spring_damping", in: animMapping)) {
                animation.expandSpringDamping = damp
            }
            if let dur = nodeDouble(nodeValue(for: "bar_animation_duration", in: animMapping)) {
                animation.barAnimationDuration = dur
            }
        }
        
        // Parse top-level display settings
        let barLength = nodeCGFloat(nodeValue(for: "bar_length", in: rootMapping)) ?? Defaults.barLength
        let barLengthExpanded = nodeCGFloat(nodeValue(for: "bar_length_expanded", in: rootMapping)) ?? Defaults.barLengthExpanded
        let nameSize = nodeCGFloat(nodeValue(for: "name_size", in: rootMapping)) ?? Defaults.nameSize
        let timeTextSize = nodeCGFloat(nodeValue(for: "time_text_size", in: rootMapping)) ?? Defaults.timeTextSize
        let timeFormat = nodeValue(for: "time_format", in: rootMapping)?.string ?? Defaults.timeFormat
        let timeShowSeconds = nodeValue(for: "time_show_seconds", in: rootMapping)?.bool ?? Defaults.timeShowSeconds
        
        return AppConfig(bars: bars, animation: animation, barLength: barLength, barLengthExpanded: barLengthExpanded, nameSize: nameSize, timeTextSize: timeTextSize, timeFormat: timeFormat, timeShowSeconds: timeShowSeconds)
    }
    
    // MARK: - YAML Serialization
    
    func toYAML() -> String {
        var lines: [String] = [
            "bar_length: \(Int(barLength))",
            "bar_length_expanded: \(Int(barLengthExpanded))",
            "name_size: \(Int(nameSize))",
            "time_text_size: \(Int(timeTextSize))",
            "time_format: \"\(timeFormat)\"",
            "time_show_seconds: \(timeShowSeconds)",
            "",
            "bars:"
        ]
        for bar in bars {
            lines.append("  \(bar.name):")
            lines.append("    rule: \"\(bar.rule)\"")
            lines.append("    color: \"\(bar.color)\"")
            lines.append("    thickness: \(Int(bar.thickness))")
            if bar.segmented {
                lines.append("    segmented: true")
                if bar.segments != Defaults.barSegments {
                    lines.append("    segments: \(bar.segments)")
                }
            }
            if bar.notify {
                lines.append("    notify: true")
            }
            if !bar.showInIdle {
                lines.append("    show_in_idle: false")
            }
            if !bar.showInExpanded {
                lines.append("    show_in_expanded: false")
            }
        }
        lines.append("")
        lines.append("animation:")
        lines.append("  expand_spring_response: \(animation.expandSpringResponse)")
        lines.append("  expand_spring_damping: \(animation.expandSpringDamping)")
        lines.append("  bar_animation_duration: \(animation.barAnimationDuration)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
