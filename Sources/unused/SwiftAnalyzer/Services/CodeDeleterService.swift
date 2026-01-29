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

    /// Deletes the specified items from their source files
    /// - Parameters:
    ///   - items: The report items to delete
    ///   - dryRun: If true, only simulates deletion without modifying files
    /// - Returns: The result of the deletion operation
    func delete(items: [ReportItem], dryRun: Bool = false) async -> DeletionResult {
        let groupedItems = Dictionary(grouping: items, by: \.file)
        var fileResults: [FileDeletionResult] = []
        var totalDeleted = 0
        var successfulFiles = 0

        for (filePath, fileItems) in groupedItems {
            let result = await deleteFromFile(filePath: filePath, items: fileItems, dryRun: dryRun)
            fileResults.append(result)

            if result.success {
                successfulFiles += 1
                totalDeleted += result.deletedCount
            }
        }

        return DeletionResult(
            fileResults: fileResults,
            totalDeleted: totalDeleted,
            totalFiles: groupedItems.count,
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
        let groupedItems = Dictionary(grouping: items, by: \.file)
        var lines: [String] = []

        for (filePath, fileItems) in groupedItems.sorted(by: { $0.key < $1.key }) {
            lines.append("File: \(filePath)")
            for item in fileItems.sorted(by: { $0.line < $1.line }) {
                lines.append("  Line \(item.line): \(item.type.rawValue) '\(item.name)'")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
