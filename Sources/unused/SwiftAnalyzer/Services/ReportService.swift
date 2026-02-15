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

    static func display(report: Report) {
        let unusedItems = report.unused
        let excludedOverrideItems = report.excluded.overrides
        let excludedProtocolItems = report.excluded.protocolImplementations
        let excludedObjcItems = report.excluded.objcItems
        let testFileCount = report.summary.testFilesExcluded
        let options = report.options

        let totalItems = unusedItems.count + excludedOverrideItems.count + excludedProtocolItems.count + excludedObjcItems.count
        let idWidth = max(1, String(totalItems).count)

        let unusedFunctionItems = unusedItems.filter { $0.type == .function }
        let unusedVariableItems = unusedItems.filter { $0.type == .variable && $0.exclusionReason != .writeOnly }
        let writeOnlyItems = unusedItems.filter { $0.exclusionReason == .writeOnly }
        let unusedClassItems = unusedItems.filter { $0.type == .class }
        let unusedEnumCaseItems = unusedItems.filter { $0.type == .enumCase }
        let unusedProtocolItems = unusedItems.filter { $0.type == .protocol }
        let unusedTypealiasItems = unusedItems.filter { $0.type == .typealias }
        let unusedParameterItems = unusedItems.filter { $0.type == .parameter }
        let unusedImportItems = unusedItems.filter { $0.type == .import }

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

        if !unusedEnumCaseItems.isEmpty {
            print("\nUnused Enum Cases:".teal.bold)
            for item in unusedEnumCaseItems {
                let parentInfo = item.parentType != nil ? " (\(item.parentType!))" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedProtocolItems.isEmpty {
            print("\nUnused Protocols:".sapphire.bold)
            for item in unusedProtocolItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedTypealiasItems.isEmpty {
            print("\nUnused Typealiases:".teal.bold)
            for item in unusedTypealiasItems {
                let parentInfo = item.parentType != nil ? " (\(item.parentType!))" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedParameterItems.isEmpty {
            print("\nUnused Function Parameters:".lavender.bold)
            for item in unusedParameterItems {
                let parentInfo = item.parentType != nil ? " in \(item.parentType!)" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !unusedImportItems.isEmpty {
            print("\nUnused Imports:".pink.bold)
            for item in unusedImportItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !writeOnlyItems.isEmpty {
            print("\nWrite-Only Variables (assigned but never read):".lavender.bold)
            for item in writeOnlyItems {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + " [write-only]".overlay0)
            }
        }

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
    }

}
