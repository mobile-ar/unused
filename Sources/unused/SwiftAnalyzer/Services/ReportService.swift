//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation

/// Service for reading and writing analysis reports in JSON format. And for displaying the report to console.
struct ReportService {

    static let reportFileName = ".unused.json"

    static func write(report: Report, to directory: String) throws {
        let directoryURL = URL(fileURLWithPath: directory)
        let outputURL = directoryURL.appendingPathComponent(reportFileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(report)
        try jsonData.write(to: outputURL)
    }

    static func read(from directory: String) throws -> Report {
        let directoryURL = URL(fileURLWithPath: directory)
        let inputURL = directoryURL.appendingPathComponent(reportFileName)

        let jsonData = try Data(contentsOf: inputURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(Report.self, from: jsonData)
    }

    static func reportExists(in directory: String) -> Bool {
        let directoryURL = URL(fileURLWithPath: directory)
        let reportURL = directoryURL.appendingPathComponent(reportFileName)
        return FileManager.default.fileExists(atPath: reportURL.path)
    }

    static func display(report: Report, output: (String) -> Void = { print($0) }) {

        let unusedItems = report.unused
        let excludedOverrideItems = report.excluded.overrides
        let excludedProtocolItems = report.excluded.protocolImplementations
        let excludedObjcItems = report.excluded.objcItems
        let excludedMainItems = report.excluded.mainTypes
        let excludedMacroItems = report.excluded.macroItems
        let testFileCount = report.summary.testFilesExcluded
        let options = report.options

        let totalItems = report.allItems.count
        let idWidth = max(1, String(totalItems).count)

        let unusedFunctionItems = unusedItems.filter { $0.type == .function }
        let unusedVariableItems = unusedItems.filter { $0.type == .variable && !$0.isWriteOnly && $0.exclusionReason != .writeOnly }
        let writeOnlyItems = unusedItems.filter { $0.isWriteOnly || $0.exclusionReason == .writeOnly }
        let unusedClassItems = unusedItems.filter { $0.type == .class }
        let unusedEnumCaseItems = unusedItems.filter { $0.type == .enumCase }
        let unusedProtocolItems = unusedItems.filter { $0.type == .protocol }
        let unusedTypealiasItems = unusedItems.filter { $0.type == .typealias }
        let unusedParameterItems = unusedItems.filter { $0.type == .parameter }
        let unusedImportItems = unusedItems.filter { $0.type == .import }

        if !unusedFunctionItems.isEmpty {
            output("\nUnused Functions:".peach.bold)
            for item in unusedFunctionItems {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedVariableItems.isEmpty {
            output("\nUnused Variables:".mauve.bold)
            for item in unusedVariableItems {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedClassItems.isEmpty {
            output("\nUnused Classes:".pink.bold)
            for item in unusedClassItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedEnumCaseItems.isEmpty {
            output("\nUnused Enum Cases:".teal.bold)
            for item in unusedEnumCaseItems {
                let parentInfo = item.parentType != nil ? " (\(item.parentType!))" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedProtocolItems.isEmpty {
            output("\nUnused Protocols:".sapphire.bold)
            for item in unusedProtocolItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedTypealiasItems.isEmpty {
            output("\nUnused Typealiases:".teal.bold)
            for item in unusedTypealiasItems {
                let parentInfo = item.parentType != nil ? " (\(item.parentType!))" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedParameterItems.isEmpty {
            output("\nUnused Local Parameter Bindings:".lavender.bold)
            output("  Signature removal is not proven safe. Review bindings manually and keep callable signatures unchanged.".overlay0)
            for item in unusedParameterItems {
                let parentInfo = item.parentType != nil ? " in \(item.parentType!)" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedImportItems.isEmpty {
            output("\nUnused Imports:".pink.bold)
            for item in unusedImportItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !writeOnlyItems.isEmpty {
            output("\nWrite-Only Variables (assigned but never read):".lavender.bold)
            for item in writeOnlyItems {
                let reason = item.exclusionReason != .none && item.exclusionReason != .writeOnly
                    ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                output("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + " [write-only]".overlay0 + reason)
            }
        }

        let totalExcluded = report.excluded.totalCount

        if totalExcluded > 0 || testFileCount > 0 {
            output("\nExcluded from results:".teal.bold)
            if !excludedOverrideItems.isEmpty {
                output("  - ".overlay0 + "\(excludedOverrideItems.count)".yellow + " override(s)".subtext0)
            }
            let confirmedProtocols = excludedProtocolItems.filter { $0.exclusionReason == .protocolImplementation }
            let uncertainProtocols = excludedProtocolItems.filter { $0.exclusionReason == .unresolvedProtocol }
            if !confirmedProtocols.isEmpty {
                output("  - ".overlay0 + "\(confirmedProtocols.count)".yellow + " protocol implementation(s)".subtext0)
            }
            if !uncertainProtocols.isEmpty {
                output("  - ".overlay0 + "\(uncertainProtocols.count)".yellow + " potential protocol witness(es) retained; requirements unavailable".subtext0)
            }
            if !excludedObjcItems.isEmpty {
                output("  - ".overlay0 + "\(excludedObjcItems.count)".yellow + " @objc/@IBAction/@IBOutlet item(s)".subtext0)
            }
            if !excludedMainItems.isEmpty {
                output("  - ".overlay0 + "\(excludedMainItems.count)".yellow + " @main entry point(s)".subtext0)
            }
            if !excludedMacroItems.isEmpty {
                output("  - ".overlay0 + "\(excludedMacroItems.count)".yellow + " potential macro dependency(ies) retained; expansion unavailable".subtext0)
            }
            if testFileCount > 0 {
                output("  - ".overlay0 + "\(testFileCount)".yellow + " test file(s)".subtext0)
            }

            if options.showExcluded {
                if !excludedMacroItems.isEmpty {
                    output("\n  Unresolved Macro Dependencies:".mauve)
                    for item in excludedMacroItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        output("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + " [unresolved macro]".overlay0)
                    }
                }
                if !excludedOverrideItems.isEmpty {
                    output("\n  Overrides:".peach)
                    for item in excludedOverrideItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        output("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !excludedProtocolItems.isEmpty {
                    output("\n  Protocol Implementations / Unresolved Witnesses:".mauve)
                    for item in excludedProtocolItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        output("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + " [\(item.exclusionReason.description)]".overlay0)
                    }
                }

                if !excludedObjcItems.isEmpty {
                    output("\n  @objc/@IBAction/@IBOutlet:".pink)
                    for item in excludedObjcItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        output("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !excludedMainItems.isEmpty {
                    output("\n  @main Entry Points:".teal)
                    for item in excludedMainItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        output("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
            }

            var flags: [String] = []
            if !options.includeOverrides && !excludedOverrideItems.isEmpty {
                flags.append("--include-overrides")
            }
            if !options.includeProtocols && excludedProtocolItems.contains(where: { $0.exclusionReason == .protocolImplementation }) {
                flags.append("--include-protocols")
            }
            if !options.includeObjc && !excludedObjcItems.isEmpty {
                flags.append("--include-objc")
            }
            if !options.includeTests && testFileCount > 0 {
                flags.append("--include-tests")
            }

            if !flags.isEmpty {
                output("\nUse \(flags.joined(separator: ", ")) to include these in results.".overlay0)
            }
            if !options.showExcluded {
                output("Use --show-excluded to see the list of excluded items.".overlay0)
            }
        }

        if unusedItems.isEmpty {
            if totalExcluded > 0 {
                output("\nNo unused code found (excluding \(totalExcluded) override/protocol/framework items)!".green.bold)
            } else {
                output("\nNo unused code found!".green.bold)
            }
        }
    }

}
