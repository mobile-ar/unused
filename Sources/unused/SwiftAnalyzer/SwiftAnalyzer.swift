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
    
    init(options: AnalyzerOptions = AnalyzerOptions(), directory: String) {
        self.options = options
        self.directory = directory
    }
    
    func analyzeFiles(_ files: [URL]) {
        let totalFiles = files.count
        
        // First pass: collect protocol requirements
        for (index, file) in files.enumerated() {
            printProgressBar(prefix: "Analyzing protocols...", current: index + 1, total: totalFiles)
            collectProtocols(at: file)
        }
        print("")
        
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
        
        // Report
        let report = report()
        
        // Write to CSV
        do {
            try CSVWriter.write(report: report, to: directory)
        } catch {
            print("Error writing .unused file: \(error)".red.bold)
        }
    }
    
    private func printProgressBar(prefix: String, current: Int, total: Int) {
        let barLength = 50
        let progress = Double(current) / Double(total)
        let filledLength = Int(progress * Double(barLength))
        let emptyLength = barLength - filledLength
        
        let filledBar = String(repeating: "█", count: filledLength).mauve
        let emptyBar = String(repeating: "░", count: emptyLength).lavender
        let percentage = String(format: "%.1f", progress * 100)
        
        print("\r \(prefix.sapphire.bold) [\(filledBar)\(emptyBar)] \(percentage)% (\(current)/\(total))", terminator: "")
        fflush(stdout)
    }
    
    private func collectProtocols(at url: URL) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ProtocolVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        for (protocolName, methods) in visitor.protocolRequirements {
            protocolRequirements[protocolName, default: Set()].formUnion(methods)
        }
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
    
    private func report() -> [Declaration] {
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
        
        // Get excluded items
        let excludedOverrides = declarations.filter { 
            $0.exclusionReason == .override && !options.includeOverrides
        }
        let excludedProtocols = declarations.filter { 
            $0.exclusionReason == .protocolImplementation && !options.includeProtocols
        }
        let excludedObjc = declarations.filter { 
            ($0.exclusionReason == .objcAttribute || 
             $0.exclusionReason == .ibAction || 
             $0.exclusionReason == .ibOutlet) && !options.includeObjc
        }
        
        let totalFindings = unusedFunctions.count + unusedVariables.count + unusedClasses.count
        let idWidth = String(totalFindings).count
        var currentId = 1
        
        if !unusedFunctions.isEmpty {
            print("\nUnused Functions:".peach.bold)
            for item in unusedFunctions {
                let reason = item.exclusionReason != .none ? " [\(reasonDescription(item.exclusionReason))]".gray : ""
                let idString = String(format: "%\(idWidth)d", currentId)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
                currentId += 1
            }
        }
        
        if !unusedVariables.isEmpty {
            print("\nUnused Variables:".mauve.bold)
            for item in unusedVariables {
                let reason = item.exclusionReason != .none ? " [\(reasonDescription(item.exclusionReason))]".gray : ""
                let idString = String(format: "%\(idWidth)d", currentId)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
                currentId += 1
            }
        }
        
        if !unusedClasses.isEmpty {
            print("\nUnused Classes:".pink.bold)
            for item in unusedClasses {
                let idString = String(format: "%\(idWidth)d", currentId)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                currentId += 1
            }
        }
        
        // Show exclusion summary
        let totalExcluded = excludedOverrides.count + excludedProtocols.count + excludedObjc.count
        let testFileCount = countExcludedTestFiles()
        
        if totalExcluded > 0 || testFileCount > 0 {
            print("\nExcluded from results:".teal.bold)
            if !excludedOverrides.isEmpty {
                print("  - ".overlay0 + "\(excludedOverrides.count)".yellow + " override(s)".subtext0)
            }
            if !excludedProtocols.isEmpty {
                print("  - ".overlay0 + "\(excludedProtocols.count)".yellow + " protocol implementation(s)".subtext0)
            }
            if !excludedObjc.isEmpty {
                print("  - ".overlay0 + "\(excludedObjc.count)".yellow + " @objc/@IBAction/@IBOutlet item(s)".subtext0)
            }
            if testFileCount > 0 {
                print("  - ".overlay0 + "\(testFileCount)".yellow + " test file(s)".subtext0)
            }
            
            if options.showExcluded {
                if !excludedOverrides.isEmpty {
                    print("\n  Overrides:".peach)
                    for item in excludedOverrides {
                        print("    - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
                
                if !excludedProtocols.isEmpty {
                    print("\n  Protocol Implementations:".mauve)
                    for item in excludedProtocols {
                        print("    - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
                
                if !excludedObjc.isEmpty {
                    print("\n  @objc/@IBAction/@IBOutlet:".pink)
                    for item in excludedObjc {
                        print("    - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
            }
            
            var flags: [String] = []
            if !options.includeOverrides && !excludedOverrides.isEmpty {
                flags.append("--include-overrides")
            }
            if !options.includeProtocols && !excludedProtocols.isEmpty {
                flags.append("--include-protocols")
            }
            if !options.includeObjc && !excludedObjc.isEmpty {
                flags.append("--include-objc")
            }
            if !options.includeTests && testFileCount > 0 {
                flags.append("--include-tests")
            }
            
            if !flags.isEmpty {
                print("\nUse \(flags.joined(separator: ", ")) to include these in results.".gray)
            }
            if !options.showExcluded {
                print("Use --show-excluded to see the list of excluded items.".gray)
            }
        }
        
        if unusedFunctions.isEmpty && unusedVariables.isEmpty && unusedClasses.isEmpty {
            if totalExcluded > 0 {
                print("\nNo unused code found (excluding \(totalExcluded) override/protocol/framework items)!".green.bold)
            } else {
                print("\nNo unused code found!".green.bold)
            }
        }
        
        return unusedFunctions + unusedVariables + unusedClasses
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
    
    private func reasonDescription(_ reason: ExclusionReason) -> String {
        switch reason {
        case .override: return "override"
        case .protocolImplementation: return "protocol"
        case .objcAttribute: return "@objc"
        case .ibAction: return "@IBAction"
        case .ibOutlet: return "@IBOutlet"
        case .none: return ""
        }
    }
}
