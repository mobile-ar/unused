//
//  Created by Fernando Romiti on 18/01/2026.
//

import Foundation

final class SwiftInterfaceParser: Sendable {
    private let sdkPath: String?
    private let architecturePrefix: String

    init(sdkPath: String?) {
        self.sdkPath = sdkPath
        #if arch(arm64)
        self.architecturePrefix = "arm64e-apple-macos"
        #else
        self.architecturePrefix = "x86_64-apple-macos"
        #endif
    }

    convenience init?() {
        guard let sdkPath = Self.getSDKPath() else { return nil }
        self.init(sdkPath: sdkPath)
    }

    func getModuleInterface(moduleName: String) -> String? {
        guard let sdkPath,
              let path = findSwiftInterfacePath(moduleName: moduleName, sdkPath: sdkPath) else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Parses a protocol or protocol alias without consulting the installed SDK.
    /// Unresolved alias members preserve known requirements and make the definition incomplete.
    func parseProtocolDefinition(protocolName: String, from moduleInterface: String) -> ProtocolDefinition? {
        SDKInterfaceIndex(moduleInterface: moduleInterface).protocolDefinition(named: protocolName)
    }

    func getProtocolDefinition(protocolName: String, inModule moduleName: String) -> ProtocolDefinition? {
        guard let interface = getModuleInterface(moduleName: moduleName) else { return nil }
        return SDKInterfaceIndex(moduleInterface: interface, moduleName: moduleName).protocolDefinition(named: protocolName)
    }

    func parseProtocolRequirements(protocolName: String, from moduleInterface: String) -> Set<String>? {
        parseProtocolDefinition(protocolName: protocolName, from: moduleInterface).map { definition in
            Set(definition.requirements.map(\.name))
        }
    }

    func getProtocolRequirements(protocolName: String, inModule moduleName: String) -> Set<String>? {
        getProtocolDefinition(protocolName: protocolName, inModule: moduleName).map { definition in
            Set(definition.requirements.map(\.name))
        }
    }

    func parseProtocolParents(protocolName: String, from moduleInterface: String) -> Set<String>? {
        parseProtocolDefinition(protocolName: protocolName, from: moduleInterface).map { definition in
            Set(definition.inheritedTypes.map(SDKInterfaceTypeReferences.leafName))
        }
    }

    func getProtocolParents(protocolName: String, inModule moduleName: String) -> Set<String>? {
        getProtocolDefinition(protocolName: protocolName, inModule: moduleName).map { definition in
            Set(definition.inheritedTypes.map(SDKInterfaceTypeReferences.leafName))
        }
    }

    func parseExportedSymbols(from moduleInterface: String) -> Set<String> {
        SDKInterfaceIndex(moduleInterface: moduleInterface).exportedSymbols
    }

    func getExportedSymbols(inModule moduleName: String) -> Set<String>? {
        guard let interface = getModuleInterface(moduleName: moduleName) else { return nil }
        return parseExportedSymbols(from: interface)
    }

    func parsePropertyWrappers(from moduleInterface: String) -> Set<String> {
        SDKInterfaceWrapperParser.wrappers(in: moduleInterface)
    }

    func getPropertyWrappers(inModule moduleName: String) -> Set<String>? {
        guard let interface = getModuleInterface(moduleName: moduleName) else { return nil }
        return parsePropertyWrappers(from: interface)
    }

    private func findSwiftInterfacePath(moduleName: String, sdkPath: String) -> String? {
        let searchPaths = [
            "\(sdkPath)/usr/lib/swift/\(moduleName).swiftmodule",
            "\(sdkPath)/System/Library/Frameworks/\(moduleName).framework/Modules/\(moduleName).swiftmodule"
        ]
        let fileManager = FileManager.default

        for basePath in searchPaths {
            let interfacePath = "\(basePath)/\(architecturePrefix).swiftinterface"
            if fileManager.fileExists(atPath: interfacePath) { return interfacePath }
            if architecturePrefix.contains("arm64e") {
                let arm64Path = "\(basePath)/arm64-apple-macos.swiftinterface"
                if fileManager.fileExists(atPath: arm64Path) { return arm64Path }
            }
        }

        for basePath in searchPaths {
            if let contents = try? fileManager.contentsOfDirectory(atPath: basePath),
               let interfaceFile = contents.sorted().first(where: { $0.contains("macos") && $0.hasSuffix(".swiftinterface") }) {
                return "\(basePath)/\(interfaceFile)"
            }
        }
        return nil
    }

    private static func getSDKPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
