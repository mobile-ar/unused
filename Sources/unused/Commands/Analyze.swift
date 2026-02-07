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

        let spinner = ConsoleSpinner()
        await spinner.start(message: "Scanning for Swift files...")
        let swiftFiles = await getSwiftFiles(in: directoryURL, includeTests: includeTests)
        await spinner.stop(success: true)
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

        ReportService.display(report: report)

        print("\nDisplaying results from existing .unused.json file.".green.bold)
        print("Run analysis again to update results.".overlay0)
    }

}
