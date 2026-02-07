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
    private var typePropertyDeclarations: [String: [PropertyInfo]] = [:] // type name -> property info
    private var writeOnlyProperties: Set<PropertyInfo> = []
    private var propertyWrappers: Set<String> = [] // dynamically detected property wrappers
    private var projectPropertyWrappers: Set<String> = [] // property wrappers defined in the project
    private let options: AnalyzerOptions
    private let directory: String
    private let swiftInterfaceClient: SwiftInterfaceClient

    init(options: AnalyzerOptions = AnalyzerOptions(), directory: String, swiftInterfaceClient: SwiftInterfaceClient = SwiftInterfaceClient()) {
        self.options = options
        self.directory = directory
        self.swiftInterfaceClient = swiftInterfaceClient
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

        // Resolve external protocols via SwiftInterface
        await protocolVisitor.resolveExternalProtocols()

        // Collect property wrappers from imported modules
        // Include SwiftUICore because many SwiftUI property wrappers (State, Binding, etc.) are defined there
        let modulesToQuery = protocolVisitor.importedModules.union(["SwiftUI", "SwiftUICore", "Combine", "Observation", "SwiftData"])
        propertyWrappers = await swiftInterfaceClient.getAllPropertyWrappers(fromModules: modulesToQuery)

        // Merge all protocol requirements
        for (protocolName, methods) in protocolVisitor.protocolRequirements {
            protocolRequirements[protocolName, default: Set()].formUnion(methods)
        }

        // Second pass: collect all declarations
        var parsedFiles: [(url: URL, source: String, sourceFile: SourceFileSyntax)] = []
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Collecting declarations...", current: index + 1, total: totalFiles)
            if let parsed = collectDeclarations(at: file) {
                parsedFiles.append(parsed)
            }
        }
        print("")

        // Third pass: collect all usage
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Collecting usage...", current: index + 1, total: totalFiles)
            collectUsage(at: file)
        }
        print("")

        // Fourth pass: detect write-only variables
        var allPropertyReads: Set<PropertyInfo> = []
        var allPropertyWrites: Set<PropertyInfo> = []
        for (index, parsed) in parsedFiles.enumerated() {
            printProgressBar(prefix: "Detecting write-only...", current: index + 1, total: parsedFiles.count)
            let (reads, writes) = collectWriteOnlyInfo(
                at: parsed.url,
                source: parsed.source,
                sourceFile: parsed.sourceFile
            )
            allPropertyReads.formUnion(reads)
            allPropertyWrites.formUnion(writes)
        }
        print("")

        writeOnlyProperties = allPropertyWrites.subtracting(allPropertyReads)

        let report = generateReport()

        do {
            try ReportService.write(report: report, to: directory)
        } catch {
            print("Error writing .unused.json file: \(error)".red.bold)
        }

        ReportService.display(report: report)
    }

    private func collectProtocols(at url: URL, using visitor: ProtocolVisitor) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }

        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    private func collectDeclarations(at url: URL) -> (url: URL, source: String, sourceFile: SourceFileSyntax)? {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("Error reading file: \(url.path)".red.bold)
            return nil
        }

        let sourceFile = Parser.parse(source: source)
        let visitor = DeclarationVisitor(
            filePath: url.path,
            protocolRequirements: protocolRequirements,
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)
        declarations.append(contentsOf: visitor.declarations)

        // Merge type conformance information
        for (typeName, protocols) in visitor.typeProtocolConformance {
            typeProtocolConformance[typeName, default: Set()].formUnion(protocols)
        }

        // Merge type property declarations
        for (typeName, properties) in visitor.typePropertyDeclarations {
            typePropertyDeclarations[typeName, default: []].append(contentsOf: properties)
        }

        // Collect project-defined property wrappers
        projectPropertyWrappers.formUnion(visitor.projectPropertyWrappers)

        return (url: url, source: source, sourceFile: sourceFile)
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

    private func collectWriteOnlyInfo(at url: URL, source: String, sourceFile: SourceFileSyntax) -> (reads: Set<PropertyInfo>, writes: Set<PropertyInfo>) {
        // Combine framework property wrappers with project-defined ones
        let allPropertyWrappers = propertyWrappers.union(projectPropertyWrappers)

        let visitor = WriteOnlyVariableVisitor(
            filePath: url.path,
            typeProperties: typePropertyDeclarations,
            propertyWrappers: allPropertyWrappers
        )
        visitor.walk(sourceFile)
        return (reads: visitor.propertyReads, writes: visitor.propertyWrites)
    }

    private func isWriteOnlyProperty(_ declaration: Declaration) -> Bool {
        guard declaration.type == .variable, let parentType = declaration.parentType else { return false }
        let key = PropertyInfo(
            name: declaration.name,
            line: declaration.line,
            filePath: declaration.file,
            typeName: parentType
        )
        return writeOnlyProperties.contains(key)
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
        case .writeOnly:
            return true // Write-only items are always included
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

        // Detect write-only variables (assigned but never read)
        let writeOnlyVariables = declarations.filter {
            $0.type == .variable &&
            usedIdentifiers.contains($0.name) &&
            isWriteOnlyProperty($0)
        }.map { declaration in
            Declaration(
                name: declaration.name,
                type: declaration.type,
                file: declaration.file,
                line: declaration.line,
                exclusionReason: .writeOnly,
                parentType: declaration.parentType
            )
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
        let unusedAll = unusedFunctions + unusedVariables + unusedClasses + writeOnlyVariables

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
