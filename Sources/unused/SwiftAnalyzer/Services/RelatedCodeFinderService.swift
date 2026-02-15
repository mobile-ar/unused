//
//  Created by Fernando Romiti on 02/02/2026.
//

import Foundation
import SwiftParser
import SwiftSyntax

struct RelatedCodeFinderService {

    func findRelatedCode(for item: ReportItem) async throws -> [RelatedDeletion] {
        switch item.type {
        case .variable:
            return try await findPropertyRelatedCode(item)
        case .function:
            return []
        case .class:
            return try await findTypeRelatedCode(item)
        case .enumCase:
            return []
        case .protocol:
            return []
        case .typealias:
            return []
        case .parameter:
            return []
        case .import:
            return []
        }
    }

    func findRelatedCode(for items: [ReportItem]) async throws -> [RelatedDeletionGroup] {
        var groups: [RelatedDeletionGroup] = []

        for item in items {
            let relatedDeletions = try await findRelatedCode(for: item)
            if !relatedDeletions.isEmpty {
                groups.append(RelatedDeletionGroup(relatedDeletions: relatedDeletions))
            }
        }

        return groups
    }

    private func findPropertyRelatedCode(_ item: ReportItem) async throws -> [RelatedDeletion] {
        var relatedDeletions: [RelatedDeletion] = []

        let source = try String(contentsOfFile: item.file, encoding: .utf8)
        let sourceLines = source.components(separatedBy: "\n")
        let sourceFile = Parser.parse(source: source)

        let initVisitor = InitAssignmentVisitor(
            propertyName: item.name,
            typeName: item.parentType,
            sourceFile: sourceFile,
            fileName: item.file
        )
        initVisitor.walk(sourceFile)

        for assignment in initVisitor.assignments {
            relatedDeletions.append(RelatedDeletion(
                filePath: item.file,
                lineRange: assignment.lineRange,
                sourceSnippet: assignment.sourceText,
                description: "Init assignment: \(assignment.sourceText)",
                parentDeclaration: item
            ))

            if let paramName = assignment.assignedFromParameter,
               let paramInfo = initVisitor.initParameters[paramName],
               paramInfo.usedOnlyForPropertyAssignment {
                let isMultiLineParameter = paramInfo.lineRange.lowerBound != paramInfo.lineRange.upperBound

                let paramLineIndex = paramInfo.lineRange.lowerBound - 1
                let isParameterOnOwnLine: Bool
                if paramLineIndex >= 0 && paramLineIndex < sourceLines.count {
                    let lineContent = sourceLines[paramLineIndex].trimmingCharacters(in: .whitespaces)
                    let paramText = paramInfo.sourceText.trimmingCharacters(in: .whitespaces)
                    isParameterOnOwnLine = lineContent == paramText ||
                                           lineContent == paramText + "," ||
                                           (lineContent.hasPrefix(paramText) && !lineContent.contains("("))
                } else {
                    isParameterOnOwnLine = false
                }

                let shouldUseLineDeletion = isMultiLineParameter || isParameterOnOwnLine

                if shouldUseLineDeletion {
                    relatedDeletions.append(RelatedDeletion(
                        filePath: item.file,
                        lineRange: paramInfo.lineRange,
                        sourceSnippet: paramInfo.sourceText,
                        description: "Init parameter '\(paramName)' only used for this property",
                        parentDeclaration: item
                    ))
                } else {
                    let partialDeletion = PartialLineDeletion(
                        line: paramInfo.lineRange.lowerBound,
                        startColumn: paramInfo.deletionStartColumn,
                        endColumn: paramInfo.deletionEndColumn
                    )
                    relatedDeletions.append(RelatedDeletion(
                        filePath: item.file,
                        lineRange: paramInfo.lineRange,
                        sourceSnippet: paramInfo.sourceText,
                        description: "Init parameter '\(paramName)' only used for this property",
                        parentDeclaration: item,
                        partialDeletion: partialDeletion
                    ))
                }
            }
        }

        let codingKeysVisitor = CodingKeysVisitor(
            typeName: item.parentType,
            propertyName: item.name,
            sourceFile: sourceFile,
            fileName: item.file
        )
        codingKeysVisitor.walk(sourceFile)

        for codingKeyCase in codingKeysVisitor.codingKeyCases {
            relatedDeletions.append(RelatedDeletion(
                filePath: item.file,
                lineRange: codingKeyCase.lineRange,
                sourceSnippet: codingKeyCase.sourceText,
                description: "CodingKeys case '\(codingKeyCase.caseName)'",
                parentDeclaration: item
            ))
        }

        for encoderCall in codingKeysVisitor.encoderCalls {
            relatedDeletions.append(RelatedDeletion(
                filePath: item.file,
                lineRange: encoderCall.lineRange,
                sourceSnippet: encoderCall.sourceText,
                description: "Encoder call for '\(encoderCall.propertyKey)'",
                parentDeclaration: item
            ))
        }

        for decoderCall in codingKeysVisitor.decoderCalls {
            relatedDeletions.append(RelatedDeletion(
                filePath: item.file,
                lineRange: decoderCall.lineRange,
                sourceSnippet: decoderCall.sourceText,
                description: "Decoder call for '\(decoderCall.propertyKey)'",
                parentDeclaration: item
            ))
        }

        return relatedDeletions
    }

    private func findTypeRelatedCode(_ item: ReportItem) async throws -> [RelatedDeletion] {
        var relatedDeletions: [RelatedDeletion] = []

        let fileURL = URL(fileURLWithPath: item.file)
        let directory = fileURL.deletingLastPathComponent()

        let swiftFiles = try findSwiftFiles(in: directory)

        for swiftFile in swiftFiles {
            let filePath = swiftFile.path
            let source = try String(contentsOf: swiftFile, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)

            let extensionVisitor = ExtensionVisitor(
                typeName: item.name,
                filePath: filePath,
                sourceFile: sourceFile
            )
            extensionVisitor.walk(sourceFile)

            for ext in extensionVisitor.extensions {
                relatedDeletions.append(RelatedDeletion(
                    filePath: ext.filePath,
                    lineRange: ext.lineRange,
                    sourceSnippet: truncateSourceSnippet(ext.sourceText),
                    description: "Extension of '\(ext.typeName)'",
                    parentDeclaration: item
                ))
            }
        }

        return relatedDeletions
    }

    private func findSwiftFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var swiftFiles: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL)
            }
        }

        return swiftFiles
    }

    private func truncateSourceSnippet(_ source: String, maxLines: Int = 5) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines {
            return source
        }

        let truncatedLines = lines.prefix(maxLines)
        return truncatedLines.joined(separator: "\n") + "\n    // ... (\(lines.count - maxLines) more lines)"
    }
}
