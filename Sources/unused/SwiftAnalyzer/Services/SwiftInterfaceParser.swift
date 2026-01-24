//
//  Created by Fernando Romiti on 18/01/2026.
//

import Foundation

final class SwiftInterfaceParser: Sendable {

    private let sdkPath: String?
    private let architecturePrefix: String

    init?() {
        guard let sdk = Self.getSDKPath() else {
            return nil
        }
        self.sdkPath = sdk

        #if arch(arm64)
        self.architecturePrefix = "arm64e-apple-macos"
        #else
        self.architecturePrefix = "x86_64-apple-macos"
        #endif
    }

    /// Get the interface of a module (e.g., "Swift", "Foundation")
    /// - Parameter moduleName: The name of the module to query
    /// - Returns: The module interface as a string, or nil if unavailable
    func getModuleInterface(moduleName: String) -> String? {
        guard let sdkPath else { return nil }

        // Try to find the .swiftinterface file for the module
        let swiftInterfacePath = findSwiftInterfacePath(moduleName: moduleName, sdkPath: sdkPath)

        guard let path = swiftInterfacePath else {
            return nil
        }

        return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// Parse protocol requirements from a module interface
    /// - Parameters:
    ///   - protocolName: The name of the protocol to find
    ///   - moduleInterface: The module interface text
    /// - Returns: A set of method/property names required by the protocol
    func parseProtocolRequirements(protocolName: String, from moduleInterface: String) -> Set<String>? {
        // Match protocol declaration with its body, handling nested braces
        guard let protocolRange = findProtocolBody(named: protocolName, in: moduleInterface) else {
            return nil
        }

        let protocolBody = String(moduleInterface[protocolRange])
        var requirements = Set<String>()

        // Extract function requirements (including operators like ==, <, etc.)
        let funcPattern = #"(?:static\s+)?func\s+([^\s\(]+)"#
        if let funcRegex = try? NSRegularExpression(pattern: funcPattern) {
            let range = NSRange(protocolBody.startIndex..., in: protocolBody)
            let matches = funcRegex.matches(in: protocolBody, range: range)
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: protocolBody) {
                    requirements.insert(String(protocolBody[nameRange]))
                }
            }
        }

        // Extract property requirements (var)
        let varPattern = #"var\s+(\w+)"#
        if let varRegex = try? NSRegularExpression(pattern: varPattern) {
            let range = NSRange(protocolBody.startIndex..., in: protocolBody)
            let matches = varRegex.matches(in: protocolBody, range: range)
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: protocolBody) {
                    requirements.insert(String(protocolBody[nameRange]))
                }
            }
        }

        // Extract associatedtype requirements
        let typePattern = #"associatedtype\s+(\w+)"#
        if let typeRegex = try? NSRegularExpression(pattern: typePattern) {
            let range = NSRange(protocolBody.startIndex..., in: protocolBody)
            let matches = typeRegex.matches(in: protocolBody, range: range)
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: protocolBody) {
                    requirements.insert(String(protocolBody[nameRange]))
                }
            }
        }

        // Extract subscript requirements
        let subscriptPattern = #"subscript\s*\("#
        if let subscriptRegex = try? NSRegularExpression(pattern: subscriptPattern) {
            let range = NSRange(protocolBody.startIndex..., in: protocolBody)
            let matches = subscriptRegex.matches(in: protocolBody, range: range)
            if !matches.isEmpty {
                requirements.insert("subscript")
            }
        }

        // Extract init requirements
        let initPattern = #"init\s*\("#
        if let initRegex = try? NSRegularExpression(pattern: initPattern) {
            let range = NSRange(protocolBody.startIndex..., in: protocolBody)
            let matches = initRegex.matches(in: protocolBody, range: range)
            if !matches.isEmpty {
                requirements.insert("init")
            }
        }

        return requirements
    }

    /// Get protocol requirements directly by querying the module
    /// - Parameters:
    ///   - protocolName: The name of the protocol
    ///   - moduleName: The module containing the protocol
    /// - Returns: A set of requirement names, or nil if unavailable
    func getProtocolRequirements(protocolName: String, inModule moduleName: String) -> Set<String>? {
        guard let interface = getModuleInterface(moduleName: moduleName) else {
            return nil
        }

        // First try to parse as a protocol directly
        if let requirements = parseProtocolRequirements(protocolName: protocolName, from: interface) {
            return requirements
        }

        // If not found as a protocol, check if it's a type alias (e.g., Codable = Encodable & Decodable)
        if let aliasedProtocols = resolveProtocolTypeAlias(name: protocolName, in: interface) {
            var combinedRequirements = Set<String>()
            for aliasedProtocol in aliasedProtocols {
                if let requirements = parseProtocolRequirements(protocolName: aliasedProtocol, from: interface) {
                    combinedRequirements.formUnion(requirements)
                }
            }
            if !combinedRequirements.isEmpty {
                return combinedRequirements
            }
        }

        return nil
    }

    /// Resolve a protocol type alias to its underlying protocols
    /// - Parameters:
    ///   - name: The type alias name (e.g., "Codable")
    ///   - moduleInterface: The module interface text
    /// - Returns: An array of protocol names the alias resolves to, or nil if not a type alias
    private func resolveProtocolTypeAlias(name: String, in moduleInterface: String) -> [String]? {
        // Look for patterns like: typealias Codable = Decodable & Encodable
        // or: public typealias Codable = Swift.Decodable & Swift.Encodable
        let pattern = #"(?:public\s+)?typealias\s+\#(name)\s*=\s*([^\n]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: moduleInterface, range: NSRange(moduleInterface.startIndex..., in: moduleInterface)),
              let aliasRange = Range(match.range(at: 1), in: moduleInterface) else {
            return nil
        }

        let aliasDefinition = String(moduleInterface[aliasRange])

        // Split by & to get individual protocol names
        let protocols = aliasDefinition
            .components(separatedBy: "&")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { component -> String in
                // Remove module prefix like "Swift." if present
                if let lastDotIndex = component.lastIndex(of: ".") {
                    return String(component[component.index(after: lastDotIndex)...])
                }
                return component
            }
            .filter { !$0.isEmpty }

        return protocols.isEmpty ? nil : protocols
    }

    /// Find the .swiftinterface file path for a given module
    private func findSwiftInterfacePath(moduleName: String, sdkPath: String) -> String? {
        // Common locations for Swift modules
        let searchPaths = [
            "\(sdkPath)/usr/lib/swift/\(moduleName).swiftmodule",
            "\(sdkPath)/System/Library/Frameworks/\(moduleName).framework/Modules/\(moduleName).swiftmodule"
        ]

        let fileManager = FileManager.default

        for basePath in searchPaths {
            // Look for architecture-specific .swiftinterface file
            let interfacePath = "\(basePath)/\(architecturePrefix).swiftinterface"
            if fileManager.fileExists(atPath: interfacePath) {
                return interfacePath
            }

            // Also try arm64 if arm64e didn't work
            if architecturePrefix.contains("arm64e") {
                let arm64Path = "\(basePath)/arm64-apple-macos.swiftinterface"
                if fileManager.fileExists(atPath: arm64Path) {
                    return arm64Path
                }
            }
        }

        // Try to find by searching the directory
        for basePath in searchPaths {
            if fileManager.fileExists(atPath: basePath) {
                if let contents = try? fileManager.contentsOfDirectory(atPath: basePath) {
                    // Find any .swiftinterface file for macos
                    if let interfaceFile = contents.first(where: { $0.contains("macos") && $0.hasSuffix(".swiftinterface") }) {
                        return "\(basePath)/\(interfaceFile)"
                    }
                }
            }
        }

        return nil
    }

    /// Find the body of a protocol definition in the source
    private func findProtocolBody(named protocolName: String, in source: String) -> Range<String.Index>? {
        // Look for "protocol ProtocolName" possibly with access modifiers
        // Need to match the protocol name followed by whitespace, colon, or opening brace
        // to avoid matching protocols that start with the same name (e.g., "Equatable" vs "EquatableBy...")
        let patterns = [
            "public protocol \(protocolName)(?:\\s|:|\\{|<)",
            "protocol \(protocolName)(?:\\s|:|\\{|<)",
            "@available[^)]*\\)\\s*public protocol \(protocolName)(?:\\s|:|\\{|<)",
            "@available[^)]*\\)\\s*protocol \(protocolName)(?:\\s|:|\\{|<)"
        ]

        var protocolStart: String.Index?

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let range = Range(match.range, in: source) {
                protocolStart = range.lowerBound
                break
            }
        }

        guard let start = protocolStart else {
            return nil
        }

        // Find the opening brace
        guard let braceStart = source[start...].firstIndex(of: "{") else {
            return nil
        }

        // Find matching closing brace
        var braceCount = 1
        var currentIndex = source.index(after: braceStart)

        while currentIndex < source.endIndex && braceCount > 0 {
            let char = source[currentIndex]
            if char == "{" {
                braceCount += 1
            } else if char == "}" {
                braceCount -= 1
            }
            currentIndex = source.index(after: currentIndex)
        }

        guard braceCount == 0 else {
            return nil
        }

        // Return the range of the body (between braces)
        let bodyStart = source.index(after: braceStart)
        let bodyEnd = source.index(before: currentIndex)

        guard bodyStart < bodyEnd else {
            return bodyStart..<bodyStart // Empty body
        }

        return bodyStart..<bodyEnd
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

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

}
