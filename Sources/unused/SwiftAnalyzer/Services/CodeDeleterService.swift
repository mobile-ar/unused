//
//  Created by Fernando Romiti on 28/01/2026.
//

import Foundation
import SwiftParser
import SwiftSyntax

/// Result of a deletion operation on a single file
struct FileDeletionResult {
    let filePath: String
    let deletedCount: Int
    let success: Bool
    let error: Error?
}

/// Result of a deletion operation across multiple files
struct DeletionResult {
    let fileResults: [FileDeletionResult]
    let totalDeleted: Int
    let totalFiles: Int
    let successfulFiles: Int

    var failedFiles: Int {
        totalFiles - successfulFiles
    }
}

struct CodeDeleterService {

    private let lineDeleterService: LineDeleterService

    init(lineDeleterService: LineDeleterService = LineDeleterService()) {
        self.lineDeleterService = lineDeleterService
    }

    /// Deletes the specified items from their source files
    /// - Parameters:
    ///   - items: The report items to delete
    ///   - dryRun: If true, only simulates deletion without modifying files
    /// - Returns: The result of the deletion operation
    func delete(items: [ReportItem], dryRun: Bool = false) async -> DeletionResult {
        let requests = items.map { DeletionRequest(item: $0, mode: .fullDeclaration) }
        return await delete(requests: requests, dryRun: dryRun)
    }

    /// Deletes based on deletion requests which may include full declarations or specific lines
    /// - Parameters:
    ///   - requests: The deletion requests specifying what to delete
    ///   - dryRun: If true, only simulates deletion without modifying files
    /// - Returns: The result of the deletion operation
    func delete(requests: [DeletionRequest], dryRun: Bool = false) async -> DeletionResult {
        let groupedRequests = Dictionary(grouping: requests, by: \.item.file)
        var fileResults: [FileDeletionResult] = []
        var totalDeleted = 0
        var successfulFiles = 0

        for (filePath, fileRequests) in groupedRequests {
            let fullDeclarationRequests = fileRequests.filter { $0.isFullDeclaration }
            let lineBasedRequests = fileRequests.filter { !$0.isFullDeclaration }

            var fileDeletedCount = 0
            var fileSuccess = true
            var fileError: Error?

            // Handle full declaration deletions
            if !fullDeclarationRequests.isEmpty {
                let items = fullDeclarationRequests.map(\.item)
                let result = await deleteFromFile(filePath: filePath, items: items, dryRun: dryRun)
                if result.success {
                    fileDeletedCount += result.deletedCount
                } else {
                    fileSuccess = false
                    fileError = result.error
                }
            }

            // Handle line-based deletions
            if !lineBasedRequests.isEmpty && fileSuccess {
                let result = lineDeleterService.deleteLines(from: filePath, requests: lineBasedRequests, dryRun: dryRun)
                if result.success {
                    fileDeletedCount += result.deletedLineCount
                } else {
                    fileSuccess = false
                    fileError = result.error
                }
            }

            let result = FileDeletionResult(
                filePath: filePath,
                deletedCount: fileDeletedCount,
                success: fileSuccess,
                error: fileError
            )
            fileResults.append(result)

            if result.success {
                successfulFiles += 1
                totalDeleted += result.deletedCount
            }
        }

        return DeletionResult(
            fileResults: fileResults,
            totalDeleted: totalDeleted,
            totalFiles: groupedRequests.count,
            successfulFiles: successfulFiles
        )
    }

    private func deleteFromFile(filePath: String, items: [ReportItem], dryRun: Bool) async -> FileDeletionResult {
        do {
            let source = try String(contentsOfFile: filePath, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)

            let targets = items.map { DeletionTarget(from: $0) }
            let visitor = DeletionVisitor(targets: targets, sourceFile: sourceFile, fileName: filePath)
            let modifiedSource = visitor.rewrite(sourceFile)

            let deletedCount = visitor.deletedCount

            if !dryRun && deletedCount > 0 {
                let cleanedSource = cleanupExtraBlankLines(modifiedSource.description)
                try cleanedSource.write(toFile: filePath, atomically: true, encoding: .utf8)
            }

            return FileDeletionResult(
                filePath: filePath,
                deletedCount: deletedCount,
                success: true,
                error: nil
            )
        } catch {
            return FileDeletionResult(
                filePath: filePath,
                deletedCount: 0,
                success: false,
                error: error
            )
        }
    }

    // TODO: Review if this works fine, looks like it might delete some top comments or extra empty lines (maybe check to use swift format if available?)
    /// Removes excessive blank lines that may result from deletion
    private func cleanupExtraBlankLines(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        var result: [String] = []
        var blankLineCount = 0

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            if isBlank {
                blankLineCount += 1
                if blankLineCount <= 2 {
                    result.append(line)
                }
            } else {
                blankLineCount = 0
                result.append(line)
            }
        }

        // Remove trailing blank lines but keep one newline at end
        while result.count > 1 && result.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            result.removeLast()
        }

        var finalResult = result.joined(separator: "\n")
        if !finalResult.hasSuffix("\n") {
            finalResult += "\n"
        }

        return finalResult
    }

    /// Previews what would be deleted without making changes
    /// - Parameter items: The report items to preview deletion for
    /// - Returns: A formatted string describing what would be deleted
    func preview(items: [ReportItem]) -> String {
        let requests = items.map { DeletionRequest(item: $0, mode: .fullDeclaration) }
        return preview(requests: requests)
    }

    /// Previews what would be deleted based on deletion requests
    /// - Parameter requests: The deletion requests to preview
    /// - Returns: A formatted string describing what would be deleted
    func preview(requests: [DeletionRequest]) -> String {
        let groupedRequests = Dictionary(grouping: requests, by: \.item.file)
        var lines: [String] = []

        for (filePath, fileRequests) in groupedRequests.sorted(by: { $0.key < $1.key }) {
            lines.append("File: \(filePath)")
            for request in fileRequests.sorted(by: { $0.item.line < $1.item.line }) {
                let item = request.item
                switch request.mode {
                case .fullDeclaration:
                    lines.append("  Line \(item.line): \(item.type.rawValue) '\(item.name)' (full declaration)")
                case .specificLines(let lineNumbers):
                    let sortedLines = lineNumbers.sorted().map(String.init).joined(separator: ", ")
                    lines.append("  Lines \(sortedLines): \(item.type.rawValue) '\(item.name)' (specific lines)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
