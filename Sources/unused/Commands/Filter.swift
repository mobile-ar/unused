//
//  Created by Fernando Romiti on 28/01/2026.
//

import ArgumentParser
import Foundation

struct Filter: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        abstract: "Filter and optionally delete unused declarations from a previous analysis"
    )

    @Argument(help: "The directory containing the .unused.json report (defaults to current directory)")
    var directory: String = FileManager.default.currentDirectoryPath

    @Option(name: .long, parsing: .upToNextOption, help: "Filter by specific item IDs (comma-separated or multiple values)")
    var ids: [Int] = []

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Filter by declaration type: function, variable, class")
    var type: [String] = []

    @Option(name: .shortAndLong, help: "Filter by file path pattern (glob pattern, e.g., 'Sources/**/*.swift')")
    var file: String?

    @Option(name: .shortAndLong, help: "Filter by declaration name pattern (regex)")
    var name: String?

    @Flag(name: .shortAndLong, help: "Include excluded items (overrides, protocol implementations, etc.) in filter results")
    var includeExcluded: Bool = false

    @Flag(name: .shortAndLong, help: "Delete the filtered declarations from source files")
    var delete: Bool = false

    @Flag(name: .long, help: "Preview what would be deleted without making changes")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt before deletion")
    var yolo: Bool = false

    func run() async throws {
        print("Unused v\(Unused.configuration.version)".blue.bold)

        guard ReportService.reportExists(in: directory) else {
            throw ValidationError("No .unused.json file found in \(directory). Run 'unused analyze' first.")
        }

        let report = try ReportService.read(from: directory)

        let parsedTypes = try parseTypes()

        let criteria = FilterCriteria(
            ids: ids.isEmpty ? nil : ids,
            types: parsedTypes.isEmpty ? nil : parsedTypes,
            filePattern: file,
            namePattern: name,
            includeExcluded: includeExcluded
        )

        if criteria.isEmpty && !includeExcluded {
            print("No filter criteria specified. Use --ids, --type, --file, or --name to filter results.".yellow)
            print("Use --help to see all available options.".overlay0)
            return
        }

        let filterService = FilterService()
        let filteredItems = filterService.filter(report: report, criteria: criteria)

        if filteredItems.isEmpty {
            print("No items match the specified filter criteria.".yellow)
            return
        }

        displayFilteredItems(filteredItems)

        let summary = filterService.summary(filteredItems)
        print("\nFiltered Results:".teal.bold)
        print("  Functions: \(summary.functions)".subtext0)
        print("  Variables: \(summary.variables)".subtext0)
        print("  Classes/Structs/Enums: \(summary.classes)".subtext0)
        print("  Total: \(filteredItems.count)".green.bold)

        if delete || dryRun {
            try await performDeletion(items: filteredItems, dryRun: dryRun)
        }
    }

    private func parseTypes() throws -> [DeclarationType] {
        var result: [DeclarationType] = []

        for typeString in type {
            switch typeString.lowercased() {
            case "function", "functions", "func":
                result.append(.function)
            case "variable", "variables", "var", "let":
                result.append(.variable)
            case "class", "classes", "struct", "structs", "enum", "enums":
                result.append(.class)
            default:
                throw ValidationError("Invalid type '\(typeString)'. Valid types: function, variable, class")
            }
        }

        return result
    }

    private func displayFilteredItems(_ items: [ReportItem]) {
        let functions = items.filter { $0.type == .function }
        let variables = items.filter { $0.type == .variable }
        let classes = items.filter { $0.type == .class }

        let totalItems = items.count
        let idWidth = max(1, String(totalItems).count)

        if !functions.isEmpty {
            print("\nFiltered Functions:".peach.bold)
            for item in functions {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !variables.isEmpty {
            print("\nFiltered Variables:".mauve.bold)
            for item in variables {
                let reason = item.exclusionReason != .none ? " [\(item.exclusionReason.description)]".overlay0 : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky + reason)
            }
        }

        if !classes.isEmpty {
            print("\nFiltered Classes/Structs/Enums:".pink.bold)
            for item in classes {
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }
    }

    private func performDeletion(items: [ReportItem], dryRun: Bool) async throws {
        let codeDeleter = CodeDeleterService()

        if dryRun {
            print("\nDry Run - Preview of deletions:".yellow.bold)
            print(codeDeleter.preview(items: items))
            print("No files were modified.".overlay0)
            return
        }

        if !yolo {
            print("\nWARNING: This will permanently delete \(items.count) declaration(s) from your source files.".red.bold)
            print("Do you want to proceed? (y/n): ".lavender, terminator: "")
            fflush(stdout)

            guard let input = readLine()?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                  input == "y" || input == "yes" else {
                print("Deletion cancelled.".yellow)
                return
            }
        }

        print("\nDeleting declarations...".peach)

        let result = await codeDeleter.delete(items: items, dryRun: false)

        print("\nDeletion complete:".bold)
        print("  Files processed: \(result.totalFiles)".subtext0)
        print("  Declarations deleted: \(result.totalDeleted)".green)

        if result.failedFiles > 0 {
            print("  Failed files: \(result.failedFiles)".red)
            for fileResult in result.fileResults where !fileResult.success {
                if let error = fileResult.error {
                    print("    \(fileResult.filePath): \(error.localizedDescription)".red)
                }
            }
        }

        print("\nNote: The .unused.json report is now outdated. Run 'unused analyze' to refresh.".overlay0)
    }
}
