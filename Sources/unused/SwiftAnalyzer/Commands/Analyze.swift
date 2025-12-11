//
//  Created by Fernando Romiti on 05/12/2025.
//

import ArgumentParser
import Foundation

struct Analyze: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Analyze Swift files for unused declarations"
    )

    @Argument(help: "The directory containing Swift files to analyze")
    var directory: String

    @Flag(name: .long, help: "Include override methods in the results")
    var includeOverrides: Bool = false

    @Flag(name: .long, help: "Include protocol implementations in the results")
    var includeProtocols: Bool = false

    @Flag(name: .long, help: "Include @objc/@IBAction/@IBOutlet items in the results")
    var includeObjc: Bool = false

    @Flag(name: .long, help: "Show detailed list of all excluded items")
    var showExcluded: Bool = false

    func run() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        print("Unused v\(Unused.configuration.version)".blue.bold)
        print("Running unused ...")

        let directoryURL = URL(fileURLWithPath: directory)

        // Check if directory exists
        guard let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory,
              isDirectory else {
            throw ValidationError("Directory does not exist: \(directory)")
        }

        let swiftFiles = getSwiftFiles(in: directoryURL)
        print("Found \(swiftFiles.count) Swift files".teal)

        let options = AnalyzerOptions(
            includeOverrides: includeOverrides,
            includeProtocols: includeProtocols,
            includeObjc: includeObjc,
            showExcluded: showExcluded
        )
        let analyzer = SwiftAnalyzer(options: options, directory: directory)
        analyzer.analyzeFiles(swiftFiles)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - startTime
        print("\nTotal processing time: \(String(format: "%.2f", totalTime))s".green.bold)
    }

}
