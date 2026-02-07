//
//  Created by Fernando Romiti on 11/12/2025.
//

import ArgumentParser
import Foundation

struct Clean: ParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Clean up all .unused.json files from the specified directory"
    )

    @Argument(help: "The directory to clean .unused.json files from (defaults to current directory)")
    var directory: String = FileManager.default.currentDirectoryPath

    func run() throws {
        print("Unused v\(Unused.configuration.version)".blue.bold)
        print("Cleaning .unused.json files...")

        let directoryURL = URL(fileURLWithPath: directory)

        guard let resourceValues = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory,
              isDirectory else {
            throw ValidationError("Directory does not exist: \(directory)")
        }

        let unusedFiles = getUnusedFiles(in: directoryURL)

        if unusedFiles.isEmpty {
            print("No .unused.json files found".yellow)
            return
        }

        print("Found \(unusedFiles.count) .unused.json file(s)".teal)

        var deletedCount = 0
        var failedCount = 0

        for file in unusedFiles {
            do {
                try FileManager.default.removeItem(at: file)
                print("Deleted: \(file.path)".green)
                deletedCount += 1
            } catch {
                print("Failed to delete \(file.path): \(error.localizedDescription)".red)
                failedCount += 1
            }
        }

        print("\nCleanup complete:".bold)
        print("  Deleted: \(deletedCount)".green)
        if failedCount > 0 {
            print("  Failed: \(failedCount)".red)
        }
    }

    private func getUnusedFiles(in directory: URL) -> [URL] {
        var unusedFiles = [URL]()
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])

        while let element = enumerator?.nextObject() as? URL {
            if !element.pathComponents.contains(".build") && element.lastPathComponent == ReportService.reportFileName {
                unusedFiles.append(element)
            }
        }

        return unusedFiles
    }

}
