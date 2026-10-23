import Foundation

/// A shader laid over 2D games.
enum ScreenFilter: String, CaseIterable, Identifiable {
    case off, crt, smooth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .crt: "CRT"
        case .smooth: "Smooth HD"
        }
    }

    /// RetroArch shader preset, relative to its shaders folder and without the .slangp/.glslp extension.
    var preset: String? {
        switch self {
        case .off: nil
        case .crt: "crt/crt-geom"
        case .smooth: "edge-smoothing/xbrz/xbrz-freescale-multipass"
        }
    }
}

/// Picture options RetroHub passes to RetroArch when it starts a game. RetroArch's own settings
/// are left alone: the options only apply to games RetroHub launches.
enum Graphics {
    static let filterKey = "screenFilter"
    static let scaleKey = "renderScale"
    static let widescreenKey = "widescreen"
    static let fullscreenKey = "fullscreen"
    static let scales = [1, 2, 3, 4]

    static var filter: ScreenFilter {
        ScreenFilter(rawValue: UserDefaults.standard.string(forKey: filterKey) ?? "") ?? .off
    }
    static var scale: Int { max(1, UserDefaults.standard.integer(forKey: scaleKey)) }
    static var widescreen: Bool { UserDefaults.standard.bool(forKey: widescreenKey) }
    /// Games start full screen unless turned off in Setup.
    static var fullscreen: Bool { UserDefaults.standard.object(forKey: fullscreenKey) as? Bool ?? true }
}

extension GameSystem {
    /// 2D systems the screen filter applies to.
    var usesScreenFilter: Bool {
        [.nes, .snes, .gb, .gbc, .gba, .genesis, .masterSystem, .gameGear, .segaCD, .sega32x, .saturn,
         .pce, .neoGeo, .atari2600, .arcade].contains(self)
    }

    /// 3D systems whose RetroArch cores can render above native resolution and in widescreen.
    var uses3DEnhancements: Bool {
        [.n64, .ps1, .dreamcast].contains(self)
    }
}

enum RetroArchGraphics {
    static let baseDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/RetroArch")

    /// Full screen or in a window, for this run only (RetroArch's own setting is left alone).
    static func windowArguments(fullscreen: Bool) -> [String] {
        fullscreen ? ["--fullscreen"] : []
    }

    /// Extra RetroArch arguments for the current graphics settings.
    static func arguments(for system: GameSystem, core: Core) -> [String] {
        var arguments = windowArguments(fullscreen: Graphics.fullscreen)
        // Settings for this run only; not saving on exit keeps them out of the user's retroarch.cfg.
        var settings: [String] = []
        let config = readConfig(baseDir.appending(path: "config/retroarch.cfg"))
        let configDir = directory(config["rgui_config_directory"], default: "config")
        if system.usesScreenFilter, let shader = shaderURL(Graphics.filter, config: config) {
            arguments.append("--set-shader=\(shader.path)")
            settings.append(#"video_shader_enable = "true""#)
        }
        let overrides = coreOptions(core.id, scale: Graphics.scale, widescreen: Graphics.widescreen)
        if system.uses3DEnhancements, !overrides.isEmpty,
           let options = try? writeCoreOptions(for: core, overrides: overrides, configDir: configDir) {
            settings += [#"global_core_options = "true""#, #"core_options_path = "\#(options.path)""#]
        }
        guard !settings.isEmpty else { return arguments }
        settings.append(#"config_save_on_exit = "false""#)
        let appended = configDir.appending(path: "RetroHub/\(core.id).cfg")
        try? FileManager.default.createDirectory(at: appended.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? (settings.joined(separator: "\n") + "\n").write(to: appended, atomically: true, encoding: .utf8)) != nil {
            arguments.append("--appendconfig=\(appended.path)")
        }
        return arguments
    }

    /// The preset file for a filter, or nil when the filter is off or RetroArch's shaders aren't downloaded.
    static func shaderURL(_ filter: ScreenFilter, config: [String: String]? = nil) -> URL? {
        guard let preset = filter.preset else { return nil }
        let config = config ?? readConfig(baseDir.appending(path: "config/retroarch.cfg"))
        // The legacy "gl" driver only runs GLSL shaders; Metal, Vulkan and glcore run Slang.
        let (folder, ext) = config["video_driver"] == "gl" ? ("shaders_glsl", "glslp") : ("shaders_slang", "slangp")
        let url = directory(config["video_shader_dir"], default: "shaders").appending(path: "\(folder)/\(preset).\(ext)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Core options that raise the internal resolution and turn on widescreen hacks.
    /// Values are the ones each core lists for these options.
    static func coreOptions(_ coreID: String, scale: Int, widescreen: Bool) -> [String: String] {
        // Some cores only offer powers of two.
        let power = scale >= 4 ? 4 : scale >= 2 ? 2 : 1
        var options: [String: String] = [:]
        switch coreID {
        case "mupen64plus_next":
            if scale > 1 {
                options["mupen64plus-EnableNativeResFactor"] = "\(scale)"
                options["mupen64plus-parallel-rdp-upscaling"] = "\(power)x"
            }
            if widescreen { options["mupen64plus-aspect"] = "16:9 adjusted" }
        case "parallel_n64":
            if scale > 1 { options["parallel-n64-upscaling"] = "\(power)x" }
            if widescreen { options["parallel-n64-aspectratiohint"] = "widescreen" }
        case "swanstation":
            if scale > 1 { options["swanstation_GPU_ResolutionScale"] = "\(scale)" }
            if widescreen {
                options["swanstation_GPU_WidescreenHack"] = "true"
                options["swanstation_Display_AspectRatio"] = "16:9"
            }
        case "flycast":
            // Dreamcast renders at 640x480; these are its 2x, 3x and 4x sizes.
            if scale > 1 { options["reicast_internal_resolution"] = "\(640 * scale)x\(480 * scale)" }
            if widescreen {
                options["reicast_widescreen_hack"] = "enabled"
                options["reicast_widescreen_cheats"] = "enabled"
            }
        case "mednafen_psx":
            if scale > 1 { options["beetle_psx_internal_resolution"] = "\(power)x" }
            if widescreen {
                options["beetle_psx_widescreen_hack"] = "enabled"
                options["beetle_psx_widescreen_hack_aspect_ratio"] = "16:9"
            }
        default:
            break
        }
        return options
    }

    /// Writes a copy of the core's current options with `overrides` applied and returns its location.
    private static func writeCoreOptions(for core: Core, overrides: [String: String], configDir: URL) throws -> URL {
        let perCore = configDir.appending(path: "\(core.name)/\(core.name).opt")
        let global = configDir.appending(path: "retroarch-core-options.cfg")
        var lines = (try? String(contentsOf: perCore, encoding: .utf8)) ?? (try? String(contentsOf: global, encoding: .utf8)) ?? ""
        lines = lines.split(separator: "\n")
            .filter { line in !overrides.keys.contains { line.hasPrefix("\($0) =") } }
            .joined(separator: "\n")
        lines += "\n" + overrides.sorted { $0.key < $1.key }.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n") + "\n"

        let dir = configDir.appending(path: "RetroHub")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let options = dir.appending(path: "\(core.id).opt")
        try lines.write(to: options, atomically: true, encoding: .utf8)
        return options
    }

    /// A folder setting from retroarch.cfg, or RetroArch's default inside its base folder.
    static func directory(_ setting: String?, default name: String) -> URL {
        guard var path = setting, !path.isEmpty, path != "default" else { return baseDir.appending(path: name) }
        if path.hasPrefix("~") {
            path = FileManager.default.homeDirectoryForCurrentUser.path + path.dropFirst()
        } else if path.hasPrefix(":") {
            path = baseDir.path + path.dropFirst()
        }
        return URL(filePath: path)
    }

    /// `key = "value"` lines from a RetroArch config file.
    static func readConfig(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            values[parts[0].trimmingCharacters(in: .whitespaces)] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return values
    }
}
