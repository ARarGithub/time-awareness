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
            try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
        
        // Create default config if not present
        if !fm.fileExists(atPath: configFileURL.path) {
            let defaultYAML = AppConfig.defaultYAML
            try? defaultYAML.write(to: configFileURL, atomically: true, encoding: .utf8)
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
        config = newConfig
        let yamlString = newConfig.toYAML()
        try? yamlString.write(to: configFileURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .configDidReload, object: nil)
    }
    
    /// Returns the path of the config file
    var configFilePath: String {
        configFileURL.path
    }
}

// MARK: - Notification

extension Notification.Name {
    static let configDidReload = Notification.Name("configDidReload")
}

// MARK: - Helpers

/// Safely extract a CGFloat from a Yams-parsed value (may be Int or Double)
private func yamlCGFloat(_ value: Any?) -> CGFloat? {
    if let d = value as? Double { return CGFloat(d) }
    if let i = value as? Int { return CGFloat(i) }
    return nil
}

private func yamlDouble(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    return nil
}

// MARK: - Data Models

struct BarConfig: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var rule: String
    var color: String
    var thickness: CGFloat
    
    static func defaultBars() -> [BarConfig] {
        [
            BarConfig(name: "seconds", rule: "60s", color: "#80C4FFCC", thickness: 4),
            BarConfig(name: "minutes", rule: "60m", color: "#FFD580CC", thickness: 4),
            BarConfig(name: "day", rule: "16h 8h", color: "#FF80ABCC", thickness: 4),
        ]
    }
}

struct AnimationConfig: Codable, Equatable {
    var idleGlow: Bool
    var expandSpringResponse: Double
    var expandSpringDamping: Double
    var barAnimationDuration: Double
    
    static let defaultAnimation = AnimationConfig(
        idleGlow: true,
        expandSpringResponse: 0.45,
        expandSpringDamping: 0.68,
        barAnimationDuration: 1.0
    )
    
    enum CodingKeys: String, CodingKey {
        case idleGlow = "idle_glow"
        case expandSpringResponse = "expand_spring_response"
        case expandSpringDamping = "expand_spring_damping"
        case barAnimationDuration = "bar_animation_duration"
    }
}

struct AppConfig: Equatable {
    var bars: [BarConfig]
    var animation: AnimationConfig
    /// Width of progress bars in points (determines Dynamic Island width)
    var barLength: CGFloat
    /// Font size of bar names in the expanded view (determines row height)
    var nameSize: CGFloat
    
    static let defaultConfig = AppConfig(
        bars: BarConfig.defaultBars(),
        animation: .defaultAnimation,
        barLength: 200,
        nameSize: 10
    )
    
    static let defaultYAML: String = """
    bar_length: 200
    name_size: 10
    
    bars:
      seconds:
        rule: "60s"
        color: "#80C4FFCC"
        thickness: 4
      minutes:
        rule: "60m"
        color: "#FFD580CC"
        thickness: 4
      day:
        rule: "16h 8h"
        color: "#FF80ABCC"
        thickness: 4
    
    animation:
      idle_glow: true
      expand_spring_response: 0.45
      expand_spring_damping: 0.68
      bar_animation_duration: 1.0
    """
    
    // MARK: - YAML Parsing
    
    static func from(yaml: String) throws -> AppConfig {
        guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
            return .defaultConfig
        }
        
        // Parse bars
        var bars: [BarConfig] = []
        if let barsDict = dict["bars"] as? [String: Any] {
            for (name, value) in barsDict {
                if let barDict = value as? [String: Any] {
                    let rule = barDict["rule"] as? String ?? "60s"
                    let color = barDict["color"] as? String ?? "#80C4FFCC"
                    let thickness = yamlCGFloat(barDict["thickness"]) ?? 4
                    bars.append(BarConfig(name: name, rule: rule, color: color, thickness: thickness))
                } else {
                    bars.append(BarConfig(name: name, rule: "60s", color: "#80C4FFCC", thickness: 4))
                }
            }
        }
        
        // Sort bars by name for stable ordering
        bars.sort { $0.name < $1.name }
        
        if bars.isEmpty {
            bars = BarConfig.defaultBars()
        }
        
        // Parse animation
        var animation = AnimationConfig.defaultAnimation
        if let animDict = dict["animation"] as? [String: Any] {
            if let idleGlow = animDict["idle_glow"] as? Bool {
                animation.idleGlow = idleGlow
            }
            if let resp = yamlDouble(animDict["expand_spring_response"]) {
                animation.expandSpringResponse = resp
            }
            if let damp = yamlDouble(animDict["expand_spring_damping"]) {
                animation.expandSpringDamping = damp
            }
            if let dur = yamlDouble(animDict["bar_animation_duration"]) {
                animation.barAnimationDuration = dur
            }
        }
        
        // Parse top-level display settings
        let barLength = yamlCGFloat(dict["bar_length"]) ?? 200
        let nameSize = yamlCGFloat(dict["name_size"]) ?? 10
        
        return AppConfig(bars: bars, animation: animation, barLength: barLength, nameSize: nameSize)
    }
    
    // MARK: - YAML Serialization
    
    func toYAML() -> String {
        var lines: [String] = [
            "bar_length: \(Int(barLength))",
            "name_size: \(Int(nameSize))",
            "",
            "bars:"
        ]
        for bar in bars {
            lines.append("  \(bar.name):")
            lines.append("    rule: \"\(bar.rule)\"")
            lines.append("    color: \"\(bar.color)\"")
            lines.append("    thickness: \(Int(bar.thickness))")
        }
        lines.append("")
        lines.append("animation:")
        lines.append("  idle_glow: \(animation.idleGlow)")
        lines.append("  expand_spring_response: \(animation.expandSpringResponse)")
        lines.append("  expand_spring_damping: \(animation.expandSpringDamping)")
        lines.append("  bar_animation_duration: \(animation.barAnimationDuration)")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
