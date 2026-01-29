//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser
import Foundation

struct Analyze: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Analyze Swift files for unused declarations"
    )

    @Argument(help: "The directory containing Swift files to analyze (defaults to current directory)")
    var directory: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Include override methods in the results")
    var includeOverrides: Bool = false

    @Flag(name: .long, help: "Include protocol implementations in the results")
    var includeProtocols: Bool = false

    @Flag(name: .long, help: "Include @objc/@IBAction/@IBOutlet items in the results")
    var includeObjc: Bool = false

    @Flag(name: .long, help: "Show detailed list of all excluded items")
    var showExcluded: Bool = false

    @Flag(name: .long, help: "Include test files in the analysis")
    var includeTests: Bool = false

    func run() async throws {
        print("Unused v\(Unused.configuration.version)".blue.bold)

        let directoryURL = URL(fileURLWithPath: directory)

        // Check if directory exists
        guard let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory,
              isDirectory else {
            throw ValidationError("Directory does not exist: \(directory)")
        }

        if ReportService.reportExists(in: directory) {
            print("Found existing .unused.json file from a previous run.".yellow)
            print("Do you want to view the previous run results? (y/n): ".lavender, terminator: "")
            fflush(stdout)

            if let input = readLine()?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
               input == "y" {
                try displayExistingResults()
                return
            } else {
                print("Running analysis again...".peach)
            }
        } else {
            print("Running unused ...")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let swiftFiles = getSwiftFiles(in: directoryURL, includeTests: includeTests)
        print("Found \(swiftFiles.count) Swift files".teal)

        let options = AnalyzerOptions(
            includeOverrides: includeOverrides,
            includeProtocols: includeProtocols,
            includeObjc: includeObjc,
            showExcluded: showExcluded,
            includeTests: includeTests
        )
        let analyzer = SwiftAnalyzer(options: options, directory: directory)
        await analyzer.analyzeFiles(swiftFiles)

        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        print("\nTotal processing time: \(String(format: "%.2f", totalTime))s".green.bold)
    }

    private func displayExistingResults() throws {
        let report = try ReportService.read(from: directory)

        if report.unused.isEmpty && report.excluded.totalCount == 0 {
            print("\nNo unused code found!".green.bold)
            return
        }

        let unusedFunctions = report.unused.filter { $0.type == .function }
        let unusedVariables = report.unused.filter { $0.type == .variable }
        let unusedClasses = report.unused.filter { $0.type == .class }

        let totalItems = report.unused.count + report.excluded.totalCount
        let idWidth = max(1, String(totalItems).count)

        if !unusedFunctions.isEmpty {
            print("\nUnused Functions:".peach.bold)
            for item in unusedFunctions {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".gray : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedVariables.isEmpty {
            print("\nUnused Variables:".mauve.bold)
            for item in unusedVariables {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".gray : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !unusedClasses.isEmpty {
            print("\nUnused Classes:".pink.bold)
            for item in unusedClasses {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        // Show exclusion summary
        let totalExcluded = report.excluded.totalCount
        let testFileCount = report.summary.testFilesExcluded

        if totalExcluded > 0 || testFileCount > 0 {
            print("\nExcluded from results:".teal.bold)
            if !report.excluded.overrides.isEmpty {
                print("  - ".overlay0 + "\(report.excluded.overrides.count)".yellow + " override(s)".subtext0)
            }
            if !report.excluded.protocolImplementations.isEmpty {
                print("  - ".overlay0 + "\(report.excluded.protocolImplementations.count)".yellow + " protocol implementation(s)".subtext0)
            }
            if !report.excluded.objcItems.isEmpty {
                print("  - ".overlay0 + "\(report.excluded.objcItems.count)".yellow + " @objc/@IBAction/@IBOutlet item(s)".subtext0)
            }
            if testFileCount > 0 {
                print("  - ".overlay0 + "\(testFileCount)".yellow + " test file(s)".subtext0)
            }

            if showExcluded {
                if !report.excluded.overrides.isEmpty {
                    print("\n  Overrides:".peach)
                    for item in report.excluded.overrides {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !report.excluded.protocolImplementations.isEmpty {
                    print("\n  Protocol Implementations:".mauve)
                    for item in report.excluded.protocolImplementations {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }

                if !report.excluded.objcItems.isEmpty {
                    print("\n  @objc/@IBAction/@IBOutlet:".pink)
                    for item in report.excluded.objcItems {
                        let idString = String(format: "%\(idWidth)d", item.id)
                        print("    [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
                    }
                }
            }

            var flags: [String] = []
            if !report.options.includeOverrides && !report.excluded.overrides.isEmpty {
                flags.append("--include-overrides")
            }
            if !report.options.includeProtocols && !report.excluded.protocolImplementations.isEmpty {
                flags.append("--include-protocols")
            }
            if !report.options.includeObjc && !report.excluded.objcItems.isEmpty {
                flags.append("--include-objc")
            }
            if !report.options.includeTests && testFileCount > 0 {
                flags.append("--include-tests")
            }

            if !flags.isEmpty {
                print("\nUse \(flags.joined(separator: ", ")) to include these in results.".gray)
            }
            if !showExcluded {
                print("Use --show-excluded to see the list of excluded items.".gray)
            }
        }

        print("\nDisplaying results from existing .unused.json file.".green.bold)
        print("Run analysis again to update results.".gray)
    }

}
