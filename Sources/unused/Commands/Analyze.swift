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

    @Option(name: .long, help: "Output format: console (default) or xcode")
    var format: OutputFormat = .console

    @Flag(name: .long, help: "Disable ANSI color output for piping to files or non-TTY environments")
    var noColor: Bool = false

    func run() async throws {
        configureOutput()

        let isXcode = format == .xcode

        if !isXcode {
            print("Unused v\(Unused.configuration.version)".blue.bold)
        }

        let directoryURL = URL(fileURLWithPath: directory)

        // Check if directory exists
        guard let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory,
              isDirectory else {
            throw ValidationError("Directory does not exist: \(directory)")
        }

        if !isXcode && ReportService.reportExists(in: directory) {
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
        } else if !isXcode {
            print("Running unused ...")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let spinner = ConsoleSpinner()
        await spinner.start(message: "Scanning for Swift files...")
        let directoryResult = await getSwiftFiles(in: directoryURL, includeTests: includeTests)
        await spinner.stop(success: true)

        if !isXcode {
            print("Found \(directoryResult.files.count) Swift files".teal)
        }

        let options = AnalyzerOptions(
            includeOverrides: includeOverrides,
            includeProtocols: includeProtocols,
            includeObjc: includeObjc,
            showExcluded: showExcluded,
            includeTests: includeTests
        )
        let analyzer = SwiftAnalyzer(
            options: options,
            directory: directory,
            excludedTestFileCount: directoryResult.excludedTestFileCount
        )
        let report = await analyzer.analyzeFiles(directoryResult.files)

        if isXcode {
            XcodeFormatter.display(report: report)
        } else {
            ReportService.display(report: report)

            let endTime = CFAbsoluteTimeGetCurrent()
            let totalTime = endTime - startTime
            print("\nTotal processing time: \(String(format: "%.2f", totalTime))s".green.bold)
        }
    }

    private func configureOutput() {
        if noColor || format == .xcode {
            OutputConfig.colorEnabled = false
            OutputConfig.interactiveEnabled = false
        }
    }

    private func displayExistingResults() throws {
        let report = try ReportService.read(from: directory)

        if format == .xcode {
            XcodeFormatter.display(report: report)
        } else {
            ReportService.display(report: report)
            print("\nDisplaying results from existing .unused.json file.".green.bold)
            print("Run analysis again to update results.".overlay0)
        }
    }

}
