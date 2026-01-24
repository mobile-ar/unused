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

        // Check for existing .unused file
        let unusedFilePath = directoryURL.appendingPathComponent(".unused")
        if FileManager.default.fileExists(atPath: unusedFilePath.path) {
            print("Found existing .unused file from a previous run.".yellow)
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
        let declarations = try CSVWriter.read(from: directory)

        if declarations.isEmpty {
            print("\nNo unused code found!".green.bold)
            return
        }

        let unusedFunctions = declarations.filter { $0.declaration.type == .function }
        let unusedVariables = declarations.filter { $0.declaration.type == .variable }
        let unusedClasses = declarations.filter { $0.declaration.type == .class }

        let totalFindings = declarations.count
        let idWidth = String(totalFindings).count

        if !unusedFunctions.isEmpty {
            print("\nUnused Functions:".peach.bold)
            for item in unusedFunctions {
                let reason = item.declaration.exclusionReason != .none ? " [\(item.declaration.exclusionReason.description)]".gray : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.declaration.name)".yellow + " in ".subtext0 + "\(item.declaration.file) : \(item.declaration.line)".sky + reason)
            }
        }

        if !unusedVariables.isEmpty {
            print("\nUnused Variables:".mauve.bold)
            for item in unusedVariables {
                let reason = item.declaration.exclusionReason != .none ? " [\(item.declaration.exclusionReason.description)]".gray : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.declaration.name)".yellow + " in ".subtext0 + "\(item.declaration.file) : \(item.declaration.line)".sky + reason)
            }
        }

        if !unusedClasses.isEmpty {
            print("\nUnused Classes:".pink.bold)
            for item in unusedClasses {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.declaration.name)".yellow + " in ".subtext0 + "\(item.declaration.file) : \(item.declaration.line)".sky)
            }
        }

        print("\nDisplaying results from existing .unused file.".green.bold)
        print("Run analysis again to update results.".gray)
    }

}
