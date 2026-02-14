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

    @Option(name: .long, help: "Filter by specific item IDs (e.g., '1-3 5 7-9' or '1,2,3')")
    var ids: String?

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Filter by declaration type: function, variable, class, enum-case, protocol")
    var type: [String] = []

    @Option(name: .shortAndLong, help: "Filter by file path pattern (glob pattern, e.g., 'Sources/**/*.swift')")
    var file: String?

    @Option(name: .shortAndLong, help: "Filter by declaration name pattern (regex)")
    var name: String?

    @Flag(name: .long, help: "Include excluded items (overrides, protocol implementations, etc.) in filter results")
    var includeExcluded: Bool = false

    @Flag(name: .shortAndLong, help: "Delete the filtered declarations from source files")
    var delete: Bool = false

    @Flag(name: .long, help: "Preview what would be deleted without making changes")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt before deletion")
    var yolo: Bool = false

    @Flag(name: .shortAndLong, help: "Interactively confirm each deletion one by one")
    var interactive: Bool = false

    func run() async throws {
        print("Unused v\(Unused.configuration.version)".blue.bold)

        guard ReportService.reportExists(in: directory) else {
            throw ValidationError("No .unused.json file found in \(directory). Run 'unused analyze' first.")
        }

        let report = try ReportService.read(from: directory)

        let parsedTypes = try parseTypes()
        let parsedIds = try parseIds()

        let criteria = FilterCriteria(
            ids: parsedIds.isEmpty ? nil : parsedIds,
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
        print("  Enum Cases: \(summary.enumCases)".subtext0)
        print("  Protocols: \(summary.protocols)".subtext0)
        print("  Total: \(filteredItems.count)".green.bold)

        if delete || dryRun {
            try await performDeletion(items: filteredItems, dryRun: dryRun)
        } else if interactive {
            print("\nNote: --interactive requires --delete to perform deletions.".yellow)
        }
    }

    private func parseIds() throws -> [Int] {
        guard let idsString = ids else {
            return []
        }

        do {
            return try LineRangeParser.parseSorted(idsString)
        } catch let error as LineRangeParserError {
            throw ValidationError(error.localizedDescription)
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
            case "enum-case", "enumcase", "case":
                result.append(.enumCase)
            case "protocol", "protocols":
                result.append(.protocol)
            default:
                throw ValidationError("Invalid type '\(typeString)'. Valid types: function, variable, class, enum-case, protocol")
            }
        }

        return result
    }

    private func displayFilteredItems(_ items: [ReportItem]) {
        let functions = items.filter { $0.type == .function }
        let variables = items.filter { $0.type == .variable }
        let classes = items.filter { $0.type == .class }
        let enumCases = items.filter { $0.type == .enumCase }
        let protocols = items.filter { $0.type == .protocol }

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

        if !enumCases.isEmpty {
            print("\nFiltered Enum Cases:".teal.bold)
            for item in enumCases {
                let parentInfo = item.parentType != nil ? " (\(item.parentType!))" : ""
                let idString = String(format: "%\(idWidth)d", item.id)
                print("  [\(idString)] - ".overlay0 + "\(item.name)".yellow + parentInfo.overlay0 + " in ".subtext0 + "\(item.file) : \(item.line)".sky)
            }
        }

        if !protocols.isEmpty {
            print("\nFiltered Protocols:".sapphire.bold)
            for item in protocols {
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

        var requestsToDelete: [DeletionRequest] = items.map { DeletionRequest(item: $0, mode: .fullDeclaration) }

        if interactive {
            let interactiveService = InteractiveDeleteService()
            requestsToDelete = try await interactiveService.confirmDeletions(items: items)

            if requestsToDelete.isEmpty {
                print("\nNo declarations selected for deletion.".yellow)
                return
            }

            let fullCount = requestsToDelete.filter { $0.isFullDeclaration }.count
            let partialCount = requestsToDelete.count - fullCount
            if partialCount > 0 {
                print("\n\(fullCount) full declaration(s) and \(partialCount) partial deletion(s) confirmed.".teal)
            } else {
                print("\n\(requestsToDelete.count) declaration(s) confirmed for deletion.".teal)
            }

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

        let result = await codeDeleter.delete(requests: requestsToDelete, dryRun: false, deleteEmptyFiles: true)

        print("\nDeletion complete:".bold)
        print("  Files processed: \(result.totalFiles)".subtext0)
        print("  Declarations deleted: \(result.totalDeleted)".green)

        if result.filesDeleted > 0 {
            print("  Empty files deleted: \(result.filesDeleted)".green)
            for filePath in result.deletedFilePaths {
                print("    \(filePath)".overlay0)
            }
        }

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
