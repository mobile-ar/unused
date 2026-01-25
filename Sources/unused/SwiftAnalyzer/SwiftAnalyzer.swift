//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation
import SwiftSyntax
import SwiftParser

class SwiftAnalyzer {
    private var declarations: [Declaration] = []
    private var usedIdentifiers = Set<String>()
    private var protocolRequirements: [String: Set<String>] = [:] // protocol name -> method names
    private var typeProtocolConformance: [String: Set<String>] = [:] // type name -> protocol names
    private let options: AnalyzerOptions
    private let directory: String
    private let swiftInterfaceClient: SwiftInterfaceClient?

    init(options: AnalyzerOptions = AnalyzerOptions(), directory: String) {
        self.options = options
        self.directory = directory
        self.swiftInterfaceClient = SwiftInterfaceClient()
    }

    func analyzeFiles(_ files: [URL]) async {
        let totalFiles = files.count

        // First pass: collect protocol requirements from project files
        let protocolVisitor = ProtocolVisitor(viewMode: .sourceAccurate, swiftInterfaceClient: swiftInterfaceClient)
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Analyzing protocols...", current: index + 1, total: totalFiles)
            collectProtocols(at: file, using: protocolVisitor)
        }
        print("")

        // Resolve external protocols via SourceKit
        await protocolVisitor.resolveExternalProtocols()

        // Merge all protocol requirements
        for (protocolName, methods) in protocolVisitor.protocolRequirements {
            protocolRequirements[protocolName, default: Set()].formUnion(methods)
        }

        // Second pass: collect all declarations
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Collecting declarations...", current: index + 1, total: totalFiles)
            collectDeclarations(at: file)
        }
        print("")

        // Third pass: collect all usage
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Collecting usage...", current: index + 1, total: totalFiles)
            collectUsage(at: file)
        }
        print("")

        // Generate and write report
        let report = generateReport()

        do {
            try ReportService.write(report: report, to: directory)
        } catch {
            print("Error writing .unused.json file: \(error)".red.bold)
        }
    }

    private func collectProtocols(at url: URL, using visitor: ProtocolVisitor) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    private func collectDeclarations(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("Error reading file: \(url.path)".red.bold)
            return
        }

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: url.path,
            protocolRequirements: protocolRequirements,
            sourceFileContent: source
        )
        visitor.walk(sourceFile)
        declarations.append(contentsOf: visitor.declarations)

        // Merge type conformance information
        for (typeName, protocols) in visitor.typeProtocolConformance {
            typeProtocolConformance[typeName, default: Set()].formUnion(protocols)
        }
    }

    private func collectUsage(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        usedIdentifiers.formUnion(visitor.usedIdentifiers)
    }

    private func shouldInclude(_ declaration: Declaration) -> Bool {
        guard declaration.shouldExcludeByDefault else {
            return true // Not excluded by default, include it
        }

        // Check if user wants to include it despite default exclusion
        switch declaration.exclusionReason {
        case .override:
            return options.includeOverrides
        case .protocolImplementation:
            return options.includeProtocols
        case .objcAttribute, .ibAction, .ibOutlet:
            return options.includeObjc
        case .none:
            return true
        }
    }

    private func generateReport() -> Report {
        let unusedFunctions = declarations.filter {
            $0.type == .function &&
            !usedIdentifiers.contains($0.name) &&
            shouldInclude($0)
        }
        let unusedVariables = declarations.filter {
            $0.type == .variable &&
            !usedIdentifiers.contains($0.name) &&
            shouldInclude($0)
        }
        let unusedClasses = declarations.filter {
            $0.type == .class &&
            !usedIdentifiers.contains($0.name) &&
            shouldInclude($0)
        }

        // Get excluded items (items that would be unused but are excluded by options)
        let excludedOverrides = declarations.filter {
            $0.type == .function &&
            !usedIdentifiers.contains($0.name) &&
            $0.exclusionReason == .override &&
            !options.includeOverrides
        }
        let excludedProtocols = declarations.filter {
            $0.type == .function &&
            !usedIdentifiers.contains($0.name) &&
            $0.exclusionReason == .protocolImplementation &&
            !options.includeProtocols
        }
        let excludedObjc = declarations.filter {
            !usedIdentifiers.contains($0.name) &&
            ($0.exclusionReason == .objcAttribute ||
             $0.exclusionReason == .ibAction ||
             $0.exclusionReason == .ibOutlet) &&
            !options.includeObjc
        }

        // Assign IDs to all items
        var currentId = 1
        let unusedAll = unusedFunctions + unusedVariables + unusedClasses

        // Calculate total items for ID width formatting
        let totalItems = unusedAll.count + excludedOverrides.count + excludedProtocols.count + excludedObjc.count
        let idWidth = max(1, String(totalItems).count)

        // Create report items for unused declarations
        var unusedItems: [ReportItem] = []
        for declaration in unusedAll {
            unusedItems.append(ReportItem(id: currentId, declaration: declaration))
            currentId += 1
        }

        // Create report items for excluded declarations
        var excludedOverrideItems: [ReportItem] = []
        for declaration in excludedOverrides {
            excludedOverrideItems.append(ReportItem(id: currentId, declaration: declaration))
            currentId += 1
        }

        var excludedProtocolItems: [ReportItem] = []
        for declaration in excludedProtocols {
            excludedProtocolItems.append(ReportItem(id: currentId, declaration: declaration))
            currentId += 1
        }

        var excludedObjcItems: [ReportItem] = []
        for declaration in excludedObjc {
            excludedObjcItems.append(ReportItem(id: currentId, declaration: declaration))
            currentId += 1
        }

        let testFileCount = countExcludedTestFiles()

        // Print unused items
        let unusedFunctionItems = unusedItems.filter { $0.type == .function }
        let unusedVariableItems = unusedItems.filter { $0.type == .variable }
        let unusedClassItems = unusedItems.filter { $0.type == .class }

        if !unusedFunctionItems.isEmpty {
            print("\nUnused Functions:".peach.bold)
            for item in unusedFunctionItems {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedVariableItems.isEmpty {
            print("\nUnused Variables:".mauve.bold)
            for item in unusedVariableItems {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedClassItems.isEmpty {
            print("\nUnused Classes:".pink.bold)
            for item in unusedClassItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        // Show exclusion summary
        let totalExcluded = excludedOverrideItems.count + excludedProtocolItems.count + excludedObjcItems.count

        if totalExcluded > 0 || testFileCount > 0 {
            print("\nExcluded from results:".teal.bold)
            if !excludedOverrideItems.isEmpty {
                print("  - ".overlay0 + "\(excludedOverrideItems.count)".yellow + " override(s)".subtext0)
            }
            if !excludedProtocolItems.isEmpty {
                print("  - ".overlay0 + "\(excludedProtocolItems.count)".yellow + " protocol implementation(s)".subtext0)
            }
            if !excludedObjcItems.isEmpty {
                print("  - ".overlay0 + "\(excludedObjcItems.count)".yellow + " @objc/@IBAction/@IBOutlet item(s)".subtext0)
            }
            if testFileCount > 0 {
                print("  - ".overlay0 + "\(testFileCount)".yellow + " test file(s)".subtext0)
            }

            if options.showExcluded {
                if !excludedOverrideItems.isEmpty {
                    print("\n  Overrides:".peach)
                    for item in excludedOverrideItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !excludedProtocolItems.isEmpty {
                    print("\n  Protocol Implementations:".mauve)
                    for item in excludedProtocolItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !excludedObjcItems.isEmpty {
                    print("\n  @objc/@IBAction/@IBOutlet:".pink)
                    for item in excludedObjcItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
            }

            var flags: [String] = []
            if !options.includeOverrides && !excludedOverrideItems.isEmpty {
                flags.append("--include-overrides")
            }
            if !options.includeProtocols && !excludedProtocolItems.isEmpty {
                flags.append("--include-protocols")
            }
            if !options.includeObjc && !excludedObjcItems.isEmpty {
                flags.append("--include-objc")
            }
            if !options.includeTests && testFileCount > 0 {
                flags.append("--include-tests")
            }

            if !flags.isEmpty {
                print("\nUse \(flags.joined(separator: ", ")) to include these in results.".overlay0)
            }
            if !options.showExcluded {
                print("Use --show-excluded to see the list of excluded items.".overlay0)
            }
        }

        if unusedItems.isEmpty {
            if totalExcluded > 0 {
                print("\nNo unused code found (excluding \(totalExcluded) override/protocol/framework items)!".green.bold)
            } else {
                print("\nNo unused code found!".green.bold)
            }
        }

        let excludedItems = ExcludedItems(
            overrides: excludedOverrideItems,
            protocolImplementations: excludedProtocolItems,
            objcItems: excludedObjcItems
        )

        return Report(
            unused: unusedItems,
            excluded: excludedItems,
            options: ReportOptions(from: options),
            testFilesExcluded: testFileCount
        )
    }

    private func countExcludedTestFiles() -> Int {
        guard !options.includeTests else { return 0 }

        let directoryURL = URL(fileURLWithPath: directory)
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
            return 0
        }

        var count = 0
        while let element = enumerator.nextObject() as? URL {
            if !element.pathComponents.contains(".build") && element.pathExtension == "swift" {
                if isTestFile(element) {
                    count += 1
                }
            }
        }

        return count
    }

}
