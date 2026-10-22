import AppKit
import Metal

/// Whether RetroHub can start each system's games on this Mac, from what's installed: the
/// emulators, their versions and the CPUs they're built for, RetroArch's cores and the firmware
/// files the cores list as required. Read-only: it changes nothing, starts nothing and runs no
/// benchmarks, and it says nothing about how well a game will run.
///
///     RetroHub --inventory [--json] [--include-documents]     (debug builds; scripts/dev-inventory.sh)
///
/// `evaluate` works on a snapshot (`Installed`), so it can be checked against made-up Macs; the
/// snapshot is taken by `Installed.current()`.
enum Compatibility {
    enum Status: String, Codable {
        /// The emulator RetroHub would use is installed, runs on this CPU, and nothing it's known
        /// to need is missing.
        case ready = "READY"
        /// Something RetroHub can name is missing: an emulator, a core or a firmware file.
        case setupRequired = "SETUP_REQUIRED"
        /// Installed, but something it needs can't be checked from outside the emulator.
        case unknown = "UNKNOWN"
        /// The installed emulator or core isn't built for this CPU, so macOS won't run it.
        case unsupported = "UNSUPPORTED"
    }

    enum Confidence: String, Codable {
        case high, medium, low
    }

    struct Result: Codable {
        let system: String
        let status: Status
        let confidence: Confidence
        /// The emulator RetroHub would start, e.g. "RetroArch (Mesen)".
        let backend: String?
        let summary: String
        let evidence: [String]
        let limitations: [String]
    }

    /// A firmware file a RetroArch core lists in its .info file.
    struct Firmware: Codable, Equatable {
        let path: String
        let description: String
        let optional: Bool
        /// nil when the folder couldn't be read.
        var present: Bool?
    }

    struct InstalledEmulator: Codable {
        let path: String
        let version: String?
        let architectures: [String]
    }

    struct InstalledCore: Codable {
        let architectures: [String]
        /// From the core's .info file; nil without one.
        let firmware: [Firmware]?
    }

    /// What's on this Mac, as far as compatibility goes.
    struct Installed: Codable {
        /// The CPU architecture programs run on natively: "x86_64" or "arm64".
        var architecture: String
        /// Apple silicon with Rosetta 2, which runs x86_64 programs.
        var rosetta = false
        /// By Emulator raw value ("retroArch").
        var emulators: [String: InstalledEmulator] = [:]
        /// By core ID ("mesen"), from the folder RetroHub starts cores from.
        var cores: [String: InstalledCore] = [:]
        var retroArch = RetroArchFolders()
    }

    struct RetroArchFolders: Codable {
        var configFound = false
        var cores = ""
        var info = ""
        var system = ""
        /// RetroArch's settings put cores somewhere else than where RetroHub looks.
        var coresElsewhere: String?
        /// The firmware folder is in a folder macOS protects (Documents, Desktop, Downloads) and
        /// wasn't read.
        var systemNotRead = false
    }

    /// The general caveats, shown once with every report.
    static let limitations = [
        "A status says whether RetroHub can start the emulator, not how well a game runs: no game was started and no benchmark ran.",
        "Firmware is checked by file name only (not by checksum), and only for RetroArch cores that list it in their .info file.",
        "Emulators are found the way RetroHub finds them: by app name in /Applications and ~/Applications.",
        "Whether an emulator's download runs on this Mac's CPU is only known once it's installed.",
    ]

    // MARK: Evaluating

    static func evaluate(_ system: GameSystem, _ installed: Installed) -> Result {
        var evidence: [String] = []
        // The first backend RetroHub would use, as Launcher.plan picks it.
        for backend in system.backends {
            switch backend {
            case .retroArch(let cores):
                guard let retroArch = installed.emulators[Emulator.retroArch.rawValue] else {
                    evidence.append("RetroArch not found")
                    continue
                }
                guard let core = cores.first(where: { installed.cores[$0.id] != nil }), let found = installed.cores[core.id] else {
                    evidence.append("RetroArch \(retroArch.version ?? "") is installed, but none of its cores for \(system.displayName) are: "
                                    + cores.map(\.file).joined(separator: ", ") + " in \(installed.retroArch.cores)")
                    if let elsewhere = installed.retroArch.coresElsewhere {
                        evidence.append("RetroArch's settings keep cores in \(elsewhere), where RetroHub doesn't look")
                    }
                    continue
                }
                return result(system, backend: "RetroArch (\(core.name))", installed: installed, evidence: evidence,
                              binaries: [("RetroArch \(retroArch.version ?? "")", retroArch.architectures), ("the \(core.name) core", found.architectures)],
                              firmware: found.firmware, firmwareNote: system.setupNote, retroArch: true)
            case .openEmu:
                guard let openEmu = installed.emulators[Emulator.openEmu.rawValue] else {
                    evidence.append("OpenEmu not found")
                    continue
                }
                return result(system, backend: "OpenEmu", installed: installed, evidence: evidence,
                              binaries: [("OpenEmu \(openEmu.version ?? "")", openEmu.architectures)],
                              firmware: nil, firmwareNote: system.setupNote, retroArch: false)
            case .app(let emulator, _):
                guard let app = installed.emulators[emulator.rawValue] else {
                    evidence.append("\(emulator.displayName) not found")
                    continue
                }
                return result(system, backend: emulator.displayName, installed: installed, evidence: evidence,
                              binaries: [("\(emulator.displayName) \(app.version ?? "")", app.architectures)],
                              firmware: nil, firmwareNote: system.setupNote, retroArch: false)
            }
        }
        let options = system.backends.map { backend -> String in
            if case .retroArch(let cores) = backend {
                return "RetroArch (with the " + cores.map(\.name).formatted(.list(type: .or)) + " core)"
            }
            return backend.emulator.displayName
        }
        return Result(system: system.displayName, status: .setupRequired, confidence: .high, backend: nil,
                      summary: "Install " + options.formatted(.list(type: .or)) + ".",
                      evidence: evidence, limitations: [])
    }

    private static func result(_ system: GameSystem, backend: String, installed: Installed, evidence: [String],
                               binaries: [(String, [String])], firmware: [Firmware]?, firmwareNote: String?,
                               retroArch: Bool) -> Result {
        var evidence = evidence
        var limitations: [String] = []
        func make(_ status: Status, _ confidence: Confidence, _ summary: String) -> Result {
            Result(system: system.displayName, status: status, confidence: confidence, backend: backend,
                   summary: summary, evidence: evidence, limitations: limitations)
        }

        for (name, architectures) in binaries {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let runs = architectures.contains(installed.architecture)
                || (installed.rosetta && architectures.contains("x86_64"))
            evidence.append("\(trimmed) is built for " + (architectures.isEmpty ? "an unknown CPU" : architectures.joined(separator: " + ")))
            if !runs {
                return make(.unsupported, architectures.isEmpty ? .medium : .high,
                            "\(trimmed) isn't built for this Mac's \(installed.architecture) CPU, so macOS won't run it. Download the build for this Mac.")
            }
        }

        if retroArch, !installed.retroArch.configFound {
            limitations.append("RetroArch's settings file wasn't found, so its default folders are assumed.")
        }
        if let firmware {
            let required = firmware.filter { !$0.optional }
            if !required.isEmpty {
                if installed.retroArch.systemNotRead || required.contains(where: { $0.present == nil }) {
                    limitations.append("RetroArch's firmware folder (\(installed.retroArch.system)) is in a protected folder and wasn't read.")
                    evidence.append("The core lists \(required.count) required firmware file(s): " + required.map(\.path).joined(separator: ", "))
                    return make(.unknown, .low, "Check the firmware files in RetroArch's system folder.")
                }
                let present = required.filter { $0.present == true }
                evidence.append("Required firmware in \(installed.retroArch.system): \(present.count) of \(required.count) present"
                                + (present.isEmpty ? "" : " (" + present.map(\.path).joined(separator: ", ") + ")"))
                if present.isEmpty {
                    return make(.setupRequired, .high, "Add firmware from your own console to RetroArch's system folder: "
                                + required.map(\.description).joined(separator: "; ") + ".")
                }
                if present.count < required.count {
                    limitations.append("The core lists several firmware files as required; often one per region is enough, so some games may still not start.")
                    return make(.unknown, .medium, "Some of the firmware the core lists is present.")
                }
            } else {
                evidence.append("The core's .info file lists no required firmware")
            }
        } else if retroArch {
            limitations.append("The core has no .info file, so its firmware needs aren't known. In RetroArch: Online Updater › Update Core Info Files.")
            if let firmwareNote {
                evidence.append(firmwareNote)
                return make(.unknown, .low, "Ready to start, but the firmware this system needs couldn't be checked.")
            }
            return make(.ready, .medium, "Ready to start in \(backend).")
        } else if let firmwareNote {
            evidence.append(firmwareNote)
            limitations.append("\(backend) keeps its own firmware and settings; RetroHub doesn't read them.")
            return make(.unknown, .medium, "Installed; the setup it needs is checked in \(backend) itself.")
        }
        return make(.ready, retroArch && !installed.retroArch.configFound ? .medium : .high, "Ready to start in \(backend).")
    }

    // MARK: Parsing

    /// The CPUs a Mach-O program or library is built for, from its first bytes: "x86_64",
    /// "arm64", or both for a universal one.
    static func architectures(header data: Data) -> [String] {
        func big32(_ offset: Int) -> UInt32? {
            guard data.count >= offset + 4 else { return nil }
            return data[data.startIndex + offset ..< data.startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func little32(_ offset: Int) -> UInt32? { big32(offset)?.byteSwapped }
        func name(_ cpu: UInt32) -> String {
            switch cpu {
            case 0x0100_0007: "x86_64"
            case 0x0100_000C: "arm64"
            case 7: "i386"
            case 12: "arm"
            case 18: "ppc"
            default: String(format: "cpu 0x%x", cpu)
            }
        }
        guard let magic = big32(0) else { return [] }
        switch magic {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            // Universal: big-endian table of slices, 20 bytes each (32 in the 64-bit form).
            guard let count = big32(4), count < 32 else { return [] }
            let size = magic == 0xCAFE_BABE ? 20 : 32
            return (0..<Int(count)).compactMap { big32(8 + $0 * size).map(name) }
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            // A single slice, little-endian.
            return little32(4).map { [name($0)] } ?? []
        default:
            return []
        }
    }

    /// The firmware entries of a RetroArch core's .info file (`firmware0_path = "scph5501.bin"`…).
    static func firmware(info text: String) -> [Firmware] {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let count = Int(values["firmware_count"] ?? "") ?? 0
        return (0..<count).compactMap { index in
            guard let path = values["firmware\(index)_path"] else { return nil }
            return Firmware(path: path, description: values["firmware\(index)_desc"] ?? path,
                            optional: values["firmware\(index)_opt"] == "true", present: nil)
        }
    }
}

extension Compatibility.Installed {
    /// Looks at this Mac. Reads the Applications folders, RetroArch's settings and cores, and
    /// RetroArch's firmware folder unless it's in Documents, Desktop or Downloads, which macOS
    /// only lets apps read after asking (`includeProtected` reads it anyway).
    static func current(includeProtected: Bool = false) -> Self {
        let translated = Host.sysctlInt("sysctl.proc_translated") == 1
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = translated ? "arm64" : "x86_64"
        #endif
        var installed = Self(architecture: architecture, rosetta: architecture == "arm64" && Host.rosettaInstalled)

        for emulator in Emulator.allCases {
            guard let executable = emulator.executableURL else { continue }
            let bundle = emulator.appURL.flatMap(Bundle.init(url:))
            installed.emulators[emulator.rawValue] = Compatibility.InstalledEmulator(
                path: (emulator.appURL ?? executable).path,
                version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                architectures: Compatibility.architectures(header: Host.header(of: executable)))
        }

        let base = RetroArchGraphics.baseDir
        let configURL = base.appending(path: "config/retroarch.cfg")
        let config = RetroArchGraphics.readConfig(configURL)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let coresDir = Launcher.retroArchCoresDir
        let configuredCores = RetroArchGraphics.directory(config["libretro_directory"], default: "cores")
        let infoDir = RetroArchGraphics.directory(config["libretro_info_path"], default: "info")
        // RetroArch's default on macOS (frontend/drivers/platform_darwin.m).
        let systemDir = config["system_directory"].flatMap { $0.isEmpty || $0 == "default" ? nil : RetroArchGraphics.directory($0, default: "system") }
            ?? home.appending(path: "Documents/RetroArch/system")
        let isProtected = ["Documents", "Desktop", "Downloads"].contains { systemDir.path.hasPrefix(home.appending(path: $0).path) }
        let readSystem = includeProtected || !isProtected
        installed.retroArch = Compatibility.RetroArchFolders(
            configFound: FileManager.default.fileExists(atPath: configURL.path), cores: coresDir.path, info: infoDir.path,
            system: systemDir.path,
            coresElsewhere: configuredCores.standardizedFileURL == coresDir.standardizedFileURL ? nil : configuredCores.path,
            systemNotRead: !readSystem)

        let files = (try? FileManager.default.contentsOfDirectory(at: coresDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasSuffix("_libretro.dylib") {
            let id = String(file.lastPathComponent.dropLast("_libretro.dylib".count))
            let info = try? String(contentsOf: infoDir.appending(path: "\(id)_libretro.info"), encoding: .utf8)
            let firmware = info.map(Compatibility.firmware(info:))?.map { item -> Compatibility.Firmware in
                var item = item
                item.present = readSystem ? FileManager.default.fileExists(atPath: systemDir.appending(path: item.path).path) : nil
                return item
            }
            installed.cores[id] = Compatibility.InstalledCore(architectures: Compatibility.architectures(header: Host.header(of: file)),
                                                     firmware: firmware)
        }
        return installed
    }
}

/// This Mac's hardware, for the report. Only what bears on running emulators: no serial
/// numbers or other identifiers.
struct Host: Codable {
    struct GPU: Codable {
        let name: String
        let metal3: Bool
        let lowPower: Bool
        let removable: Bool
        let workingSetGB: Double
    }

    struct Volume: Codable {
        let path: String
        let name: String
        let availableGB: Double
        let totalGB: Double
    }

    let macOS: String
    let model: String
    let cpu: String
    let architecture: String
    let rosettaTranslated: Bool
    let cores: Int
    let threads: Int
    /// x86 vector extensions some emulators require or use when present.
    let cpuFeatures: [String]
    let memoryGB: Double
    let gpus: [GPU]
    let volumes: [Volume]

    static func current(volumes paths: [URL]) -> Host {
        let features = [("hw.optional.sse4_2", "SSE4.2"), ("hw.optional.avx1_0", "AVX"), ("hw.optional.avx2_0", "AVX2"),
                        ("hw.optional.avx512f", "AVX-512"), ("hw.optional.arm64", "ARM64")]
            .filter { sysctlInt($0.0) == 1 }.map(\.1)
        let gpus = MTLCopyAllDevices().map {
            GPU(name: $0.name, metal3: $0.supportsFamily(.metal3), lowPower: $0.isLowPower, removable: $0.isRemovable,
                workingSetGB: Double($0.recommendedMaxWorkingSetSize) / 1_073_741_824)
        }
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        let volumes = paths.compactMap { url -> Volume? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return Volume(path: url.path, name: values.volumeName ?? "?",
                          availableGB: Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000,
                          totalGB: Double(values.volumeTotalCapacity ?? 0) / 1_000_000_000)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let translated = sysctlInt("sysctl.proc_translated") == 1
        return Host(macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) (\(sysctlString("kern.osversion") ?? "?"))",
                    model: sysctlString("hw.model") ?? "?",
                    cpu: sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.model") ?? "?",
                    architecture: translated ? "arm64" : sysctlString("hw.machine") ?? "?",
                    rosettaTranslated: translated,
                    cores: sysctlInt("hw.physicalcpu") ?? 0, threads: sysctlInt("hw.logicalcpu") ?? 0,
                    cpuFeatures: features,
                    memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                    gpus: gpus, volumes: volumes)
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
    }

    static var rosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    /// The first 4 KB of a file: enough for a Mach-O header and a universal binary's table.
    static func header(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4096)) ?? Data()
    }
}

extension Compatibility {
    /// Everything `--inventory` prints.
    struct Report: Codable {
        let generated: Date
        let host: Host
        let installed: Installed
        let systems: [Result]
        let limitations: [String]

        static func current(includeProtected: Bool = false) -> Report {
            let installed = Installed.current(includeProtected: includeProtected)
            return Report(generated: .now, host: Host.current(volumes: [FileManager.default.homeDirectoryForCurrentUser]),
                          installed: installed, systems: GameSystem.allCases.map { evaluate($0, installed) },
                          limitations: Compatibility.limitations)
        }

        var json: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        }

        var text: String {
            func gb(_ value: Double) -> String {
                value >= 1000 ? String(format: "%.1f TB", value / 1000) : String(format: value >= 100 ? "%.0f GB" : "%.1f GB", value)
            }
            var lines = ["RetroHub compatibility inventory (read-only), \(generated.formatted(date: .abbreviated, time: .shortened))", "",
                         "This Mac",
                         "  macOS  \(host.macOS) · \(host.model)",
                         "  CPU    \(host.cpu) · \(host.architecture)\(host.rosettaTranslated ? " (this report ran under Rosetta)" : "") · \(host.cores) cores, \(host.threads) threads",
                         "         " + (host.cpuFeatures.isEmpty ? "no vector extensions reported" : host.cpuFeatures.joined(separator: " · ")),
                         "  RAM    \(gb(host.memoryGB))"]
            lines += host.gpus.map { gpu in
                "  GPU    \(gpu.name) · Metal 3: \(gpu.metal3 ? "yes" : "no")\(gpu.lowPower ? " · low power" : "")\(gpu.removable ? " · external" : "") · \(gb(gpu.workingSetGB)) usable"
            }
            lines += host.volumes.map { "  Disk   \($0.name): \(gb($0.availableGB)) free of \(gb($0.totalGB))" }

            lines += ["", "Emulators (by app name in /Applications and ~/Applications)"]
            for emulator in Emulator.allCases {
                let found = installed.emulators[emulator.rawValue]
                let name = emulator.displayName.padding(toLength: 10, withPad: " ", startingAt: 0)
                lines.append("  \(name) " + (found.map { "\($0.version ?? "version ?") · \($0.architectures.joined(separator: " + ")) · \($0.path)" } ?? "not installed"))
            }

            let folders = installed.retroArch
            lines += ["", "RetroArch",
                      "  settings  " + (folders.configFound ? "found" : "not found: default folders assumed"),
                      "  cores     \(folders.cores): " + (installed.cores.isEmpty ? "none" : installed.cores.keys.sorted().joined(separator: ", ")),
                      "  info      \(folders.info)",
                      "  firmware  \(folders.system)" + (folders.systemNotRead ? " (protected folder, not read; --include-documents reads it)" : "")]
            if let elsewhere = folders.coresElsewhere { lines.append("  note      RetroArch's settings keep cores in \(elsewhere)") }

            lines += ["", "Systems"]
            for result in systems {
                let name = result.system.padding(toLength: 18, withPad: " ", startingAt: 0)
                let status = result.status.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
                lines.append("  \(name)\(status)\(result.confidence.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0))\(result.summary)")
                lines += result.evidence.map { "      evidence  \($0)" }
                lines += result.limitations.map { "      limit     \($0)" }
            }
            lines += ["", "Limitations"] + limitations.map { "  - \($0)" }
            return lines.joined(separator: "\n")
        }
    }
}
