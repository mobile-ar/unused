//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation
import SwiftSyntax
import SwiftParser

class SwiftAnalyzer {
    private var declarations: [Declaration] = []
    private var usedIdentifiers = Set<String>()
    private var qualifiedMemberUsages = Set<QualifiedUsage>()
    private var unqualifiedMemberUsages = Set<String>()
    private var bareIdentifierUsages = Set<String>()
    private var protocolRequirements: [String: Set<String>] = [:]
    private var protocolInheritance: [String: Set<String>] = [:]
    private var projectDefinedProtocols: Set<String> = []
    private var importedModules: Set<String> = []
    private var conformedProtocols: Set<String> = []
    private var typeProtocolConformance: [String: Set<String>] = [:]
    private var typePropertyDeclarations: [String: [PropertyInfo]] = [:]
    private var writeOnlyProperties: Set<PropertyInfo> = []
    private var propertyWrappers: Set<String> = []
    private var projectPropertyWrappers: Set<String> = []
    private let options: AnalyzerOptions
    private let directory: String
    private let swiftInterfaceClient: SwiftInterfaceClient
    private let excludedTestFileCount: Int

    init(
        options: AnalyzerOptions = AnalyzerOptions(),
        directory: String,
        swiftInterfaceClient: SwiftInterfaceClient = SwiftInterfaceClient(),
        excludedTestFileCount: Int = 0
    ) {
        self.options = options
        self.directory = directory
        self.swiftInterfaceClient = swiftInterfaceClient
        self.excludedTestFileCount = excludedTestFileCount
    }

    func analyzeFiles(_ files: [URL]) async {
        let totalFiles = files.count

        // Step 1: Parse all files in parallel (read from disk once, parse once)
        let parseTracker = ProgressTracker(total: totalFiles, prefix: "Parsing files...")
        let parsedFiles: [ParsedFile] = await withTaskGroup(of: ParsedFile?.self) { group in
            for file in files {
                group.addTask {
                    await parseTracker.increment()
                    guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                        return nil
                    }
                    let sourceFile = Parser.parse(source: source)
                    return ParsedFile(url: file, source: source, sourceFile: sourceFile)
                }
            }
            var results: [ParsedFile] = []
            results.reserveCapacity(totalFiles)
            for await parsed in group {
                if let parsed {
                    results.append(parsed)
                }
            }
            return results
        }
        await parseTracker.finish()

        let parsedFileCount = parsedFiles.count

        // Step 2: Collect protocol information in parallel
        let protocolTracker = ProgressTracker(total: parsedFileCount, prefix: "Analyzing protocols...")
        let protocolResults: [ProtocolVisitorResult] = await withTaskGroup(of: ProtocolVisitorResult.self) { group in
            for parsed in parsedFiles {
                group.addTask {
                    await protocolTracker.increment()
                    let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
                    visitor.walk(parsed.sourceFile)
                    return visitor.result
                }
            }
            var results: [ProtocolVisitorResult] = []
            results.reserveCapacity(parsedFileCount)
            for await result in group {
                results.append(result)
            }
            return results
        }
        await protocolTracker.finish()

        // Merge protocol results
        mergeProtocolResults(protocolResults)

        // Scan dependency source files for protocol definitions (third-party packages)
        let dependencyFiles = getDependencyProtocolFiles(in: directory)
        if !dependencyFiles.isEmpty {
            let depTracker = ProgressTracker(total: dependencyFiles.count, prefix: "Scanning dependency protocols...")
            let depResults: [ProtocolVisitorResult] = await withTaskGroup(of: ProtocolVisitorResult?.self) { group in
                for file in dependencyFiles {
                    group.addTask {
                        await depTracker.increment()
                        guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                            return nil
                        }
                        let sourceFile = Parser.parse(source: source)
                        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
                        visitor.walk(sourceFile)
                        return visitor.result
                    }
                }
                var results: [ProtocolVisitorResult] = []
                for await result in group {
                    if let result {
                        results.append(result)
                    }
                }
                return results
            }
            await depTracker.finish()

            mergeProtocolResults(depResults)
        }

        // Resolve external protocols via SwiftInterface
        await resolveExternalProtocols()

        // Propagate inherited protocol requirements transitively
        resolveInheritedRequirements()

        // Collect property wrappers from imported modules
        let modulesToQuery = importedModules.union(["SwiftUI", "SwiftUICore", "Combine", "Observation", "SwiftData"])
        propertyWrappers = await swiftInterfaceClient.getAllPropertyWrappers(fromModules: modulesToQuery)

        // Step 3: Collect all declarations in parallel
        let declTracker = ProgressTracker(total: parsedFileCount, prefix: "Collecting declarations...")
        let declarationResults: [DeclarationVisitorResult] = await withTaskGroup(of: DeclarationVisitorResult.self) { group in
            let requirements = protocolRequirements
            for parsed in parsedFiles {
                group.addTask {
                    await declTracker.increment()
                    let visitor = DeclarationVisitor(
                        filePath: parsed.url.path,
                        protocolRequirements: requirements,
                        sourceFile: parsed.sourceFile
                    )
                    visitor.walk(parsed.sourceFile)
                    return DeclarationVisitorResult(
                        declarations: visitor.declarations,
                        typeProtocolConformance: visitor.typeProtocolConformance,
                        typePropertyDeclarations: visitor.typePropertyDeclarations,
                        projectPropertyWrappers: visitor.projectPropertyWrappers
                    )
                }
            }
            var results: [DeclarationVisitorResult] = []
            results.reserveCapacity(parsedFileCount)
            for await result in group {
                results.append(result)
            }
            return results
        }
        await declTracker.finish()

        // Merge declaration results
        mergeDeclarationResults(declarationResults)

        // Post-process: mark enum cases belonging to CaseIterable enums
        markCaseIterableEnumCases()

        // Step 4: Collect usage and write-only info in parallel (combined per-file)
        let knownTypeNames = Set(declarations.filter { $0.type == .class }.map(\.name))
        let allPropertyWrappers = propertyWrappers.union(projectPropertyWrappers)
        let allTypePropertyDeclarations = typePropertyDeclarations

        let usageTracker = ProgressTracker(total: parsedFileCount, prefix: "Collecting usage...")
        let combinedResults: [(usage: UsageVisitorResult, writeOnly: WriteOnlyVisitorResult)] = await withTaskGroup(
            of: (UsageVisitorResult, WriteOnlyVisitorResult).self
        ) { group in
            for parsed in parsedFiles {
                group.addTask {
                    await usageTracker.increment()

                    // Usage visitor
                    let usageVisitor = UsageVisitor(knownTypeNames: knownTypeNames)
                    usageVisitor.walk(parsed.sourceFile)
                    let usageResult = UsageVisitorResult(
                        usedIdentifiers: usageVisitor.usedIdentifiers,
                        qualifiedMemberUsages: usageVisitor.qualifiedMemberUsages,
                        unqualifiedMemberUsages: usageVisitor.unqualifiedMemberUsages,
                        bareIdentifierUsages: usageVisitor.bareIdentifierUsages
                    )

                    // Write-only visitor (runs on the same AST in the same task)
                    let writeOnlyVisitor = WriteOnlyVariableVisitor(
                        filePath: parsed.url.path,
                        typeProperties: allTypePropertyDeclarations,
                        propertyWrappers: allPropertyWrappers
                    )
                    writeOnlyVisitor.walk(parsed.sourceFile)
                    let writeOnlyResult = WriteOnlyVisitorResult(
                        propertyReads: writeOnlyVisitor.propertyReads,
                        propertyWrites: writeOnlyVisitor.propertyWrites
                    )

                    return (usageResult, writeOnlyResult)
                }
            }
            var results: [(UsageVisitorResult, WriteOnlyVisitorResult)] = []
            results.reserveCapacity(parsedFileCount)
            for await result in group {
                results.append(result)
            }
            return results
        }
        await usageTracker.finish()

        // Merge usage and write-only results
        var allPropertyReads: Set<PropertyInfo> = []
        var allPropertyWrites: Set<PropertyInfo> = []
        for (usageResult, writeOnlyResult) in combinedResults {
            usedIdentifiers.formUnion(usageResult.usedIdentifiers)
            qualifiedMemberUsages.formUnion(usageResult.qualifiedMemberUsages)
            unqualifiedMemberUsages.formUnion(usageResult.unqualifiedMemberUsages)
            bareIdentifierUsages.formUnion(usageResult.bareIdentifierUsages)
            allPropertyReads.formUnion(writeOnlyResult.propertyReads)
            allPropertyWrites.formUnion(writeOnlyResult.propertyWrites)
        }

        writeOnlyProperties = allPropertyWrites.subtracting(allPropertyReads)

        let report = generateReport()

        do {
            try ReportService.write(report: report, to: directory)
        } catch {
            print("Error writing .unused.json file: \(error)".red.bold)
        }

        ReportService.display(report: report)
    }

    private func mergeProtocolResults(_ results: [ProtocolVisitorResult]) {
        for result in results {
            for (protocolName, methods) in result.protocolRequirements {
                protocolRequirements[protocolName, default: Set()].formUnion(methods)
            }
            for (protocolName, parents) in result.protocolInheritance {
                protocolInheritance[protocolName, default: Set()].formUnion(parents)
            }
            projectDefinedProtocols.formUnion(result.projectDefinedProtocols)
            importedModules.formUnion(result.importedModules)
            conformedProtocols.formUnion(result.conformedProtocols)
        }
    }

    private func mergeDeclarationResults(_ results: [DeclarationVisitorResult]) {
        for result in results {
            declarations.append(contentsOf: result.declarations)
            for (typeName, protocols) in result.typeProtocolConformance {
                typeProtocolConformance[typeName, default: Set()].formUnion(protocols)
            }
            for (typeName, properties) in result.typePropertyDeclarations {
                typePropertyDeclarations[typeName, default: []].append(contentsOf: properties)
            }
            projectPropertyWrappers.formUnion(result.projectPropertyWrappers)
        }
    }

    private func resolveExternalProtocols() async {
        let resolver = ProtocolResolver(
            protocolRequirements: protocolRequirements,
            protocolInheritance: protocolInheritance,
            projectDefinedProtocols: projectDefinedProtocols,
            importedModules: importedModules,
            conformedProtocols: conformedProtocols,
            swiftInterfaceClient: swiftInterfaceClient
        )
        await resolver.resolveExternalProtocols()
        protocolRequirements = resolver.protocolRequirements
        protocolInheritance = resolver.protocolInheritance
    }

    private func resolveInheritedRequirements() {
        let resolver = ProtocolResolver(
            protocolRequirements: protocolRequirements,
            protocolInheritance: protocolInheritance,
            projectDefinedProtocols: projectDefinedProtocols,
            importedModules: importedModules,
            conformedProtocols: conformedProtocols,
            swiftInterfaceClient: swiftInterfaceClient
        )
        resolver.resolveInheritedRequirements()
        protocolRequirements = resolver.protocolRequirements
        protocolInheritance = resolver.protocolInheritance
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
            return true
        }

        switch declaration.exclusionReason {
        case .override:
            return options.includeOverrides
        case .protocolImplementation:
            return options.includeProtocols
        case .objcAttribute, .ibAction, .ibOutlet:
            return options.includeObjc
        case .writeOnly:
            return true // Write-only items are always included
        case .caseIterable:
            return false // CaseIterable enum cases are excluded by default
        case .none:
            return true
        }
    }

    private func isUsed(_ declaration: Declaration) -> Bool {
        let name = declaration.name

        guard let parentType = declaration.parentType else {
            return usedIdentifiers.contains(name)
        }

        if qualifiedMemberUsages.contains(QualifiedUsage(typeName: parentType, memberName: name)) {
            return true
        }

        if bareIdentifierUsages.contains(name) {
            return true
        }

        if unqualifiedMemberUsages.contains(name) {
            return true
        }

        return false
    }

    private func markCaseIterableEnumCases() {
        let caseIterableEnums = typeProtocolConformance
            .filter { $0.value.contains("CaseIterable") }
            .map(\.key)
        let caseIterableSet = Set(caseIterableEnums)

        guard !caseIterableSet.isEmpty else { return }

        declarations = declarations.map { declaration in
            guard declaration.type == .enumCase,
                  let parentType = declaration.parentType,
                  caseIterableSet.contains(parentType) else {
                return declaration
            }
            return Declaration(
                name: declaration.name,
                type: declaration.type,
                file: declaration.file,
                line: declaration.line,
                exclusionReason: .caseIterable,
                parentType: declaration.parentType
            )
        }
    }

    private func generateReport() -> Report {
        let unusedFunctions = declarations.filter {
            $0.type == .function &&
            !isUsed($0) &&
            shouldInclude($0)
        }
        let unusedVariables = declarations.filter {
            $0.type == .variable &&
            !isUsed($0) &&
            shouldInclude($0)
        }
        let unusedClasses = declarations.filter {
            $0.type == .class &&
            !isUsed($0) &&
            shouldInclude($0)
        }
        let unusedEnumCases = declarations.filter {
            $0.type == .enumCase &&
            !isUsed($0) &&
            shouldInclude($0)
        }
        let unusedProtocols = declarations.filter {
            $0.type == .protocol &&
            !isUsed($0) &&
            shouldInclude($0)
        }

        let writeOnlyVariables = declarations.filter {
            $0.type == .variable &&
            isUsed($0) &&
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

        let excludedOverrides = declarations.filter {
            $0.type == .function &&
            !isUsed($0) &&
            $0.exclusionReason == .override &&
            !options.includeOverrides
        }
        let excludedProtocols = declarations.filter {
            !isUsed($0) &&
            $0.exclusionReason == .protocolImplementation &&
            !options.includeProtocols
        }
        let excludedObjc = declarations.filter {
            !isUsed($0) &&
            ($0.exclusionReason == .objcAttribute ||
             $0.exclusionReason == .ibAction ||
             $0.exclusionReason == .ibOutlet) &&
            !options.includeObjc
        }

        var currentId = 1
        let unusedAll = unusedFunctions + unusedVariables + unusedClasses + unusedEnumCases + unusedProtocols + writeOnlyVariables

        var unusedItems: [ReportItem] = []
        for declaration in unusedAll {
            unusedItems.append(ReportItem(id: currentId, declaration: declaration))
            currentId += 1
        }

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

        let excludedItems = ExcludedItems(
            overrides: excludedOverrideItems,
            protocolImplementations: excludedProtocolItems,
            objcItems: excludedObjcItems
        )

        return Report(
            unused: unusedItems,
            excluded: excludedItems,
            options: ReportOptions(from: options),
            testFilesExcluded: excludedTestFileCount
        )
    }

    func getDependencyProtocolFiles(in directory: String) -> [URL] {
        let directoryURL = URL(fileURLWithPath: directory)
        let checkoutsURL = directoryURL.appendingPathComponent(".build/checkouts")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: checkoutsURL.path) else {
            return []
        }

        var protocolFiles: [URL] = []
        guard let enumerator = fileManager.enumerator(at: checkoutsURL, includingPropertiesForKeys: nil) else {
            return []
        }

        while let element = enumerator.nextObject() as? URL {
            guard element.pathExtension == "swift"
                && !element.pathComponents.contains("Tests")
                && !element.pathComponents.contains("Benchmarks")
                && !element.pathComponents.contains("Examples") else {
                continue
            }

            guard let content = try? String(contentsOf: element, encoding: .utf8),
                  content.contains("protocol ") else {
                continue
            }

            protocolFiles.append(element)
        }

        return protocolFiles
    }

}
