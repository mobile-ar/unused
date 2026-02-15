//
//  Created by Fernando Romiti on 01/02/2026.
//

import Foundation

enum InteractiveResponse: Equatable {
    case yes
    case no
    case all
    case quit
    case openXcode
    case openZed
    case lineRange(Set<Int>)
}

protocol InteractiveInputProvider {
    func readLine() -> String?
}

struct StandardInputProvider: InteractiveInputProvider {
    func readLine() -> String? {
        Swift.readLine()
    }
}

struct InteractiveDeleteService {

    private let inputProvider: InteractiveInputProvider
    private let editorOpener: EditorOpenerProtocol
    private let relatedCodeFinder: RelatedCodeFinderService

    init(
        inputProvider: InteractiveInputProvider = StandardInputProvider(),
        editorOpener: EditorOpenerProtocol = EditorOpener(),
        relatedCodeFinder: RelatedCodeFinderService = RelatedCodeFinderService()
    ) {
        self.inputProvider = inputProvider
        self.editorOpener = editorOpener
        self.relatedCodeFinder = relatedCodeFinder
    }

    func confirmDeletions(items: [ReportItem]) async throws -> [DeletionRequest] {
        var confirmedRequests: [DeletionRequest] = []
        var deleteAllRemaining = false
        var deleteAllRelated = false

        for (index, item) in items.enumerated() {
            if deleteAllRemaining {
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))
                let relatedRequests = try await processRelatedDeletions(for: item)
                confirmedRequests.append(contentsOf: relatedRequests)
                continue
            }

            let result = try promptForItem(item: item, index: index, total: items.count)

            switch result {
            case .yes:
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))

                let relatedDeletions = try await relatedCodeFinder.findRelatedCode(for: item)
                if !relatedDeletions.isEmpty {
                    let relatedRequests = try promptRelatedDeletions(relatedDeletions, for: item, deleteAll: &deleteAllRelated)
                    confirmedRequests.append(contentsOf: relatedRequests)
                }
            case .no:
                continue
            case .all:
                deleteAllRemaining = true
                deleteAllRelated = true
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))
                let relatedRequests = try await processRelatedDeletions(for: item)
                confirmedRequests.append(contentsOf: relatedRequests)
            case .quit:
                return confirmedRequests
            case .lineRange(let lines):
                confirmedRequests.append(DeletionRequest(item: item, mode: .specificLines(lines)))
            default:
                continue
            }
        }

        return confirmedRequests
    }

    private func processRelatedDeletions(for item: ReportItem) async throws -> [DeletionRequest] {
        let relatedDeletions = try await relatedCodeFinder.findRelatedCode(for: item)
        return relatedDeletions.map { DeletionRequest.fromRelatedDeletion($0) }
    }

    private func promptRelatedDeletions(_ relatedDeletions: [RelatedDeletion], for item: ReportItem, deleteAll: inout Bool) throws -> [DeletionRequest] {
        var requests: [DeletionRequest] = []

        print("\n" + "─".repeated(60).mauve)
        print("Found \(relatedDeletions.count) related code section(s) for '\(item.name)'".mauve.bold)
        print("─".repeated(60).mauve)

        for (index, related) in relatedDeletions.enumerated() {
            if deleteAll {
                requests.append(DeletionRequest.fromRelatedDeletion(related))
                continue
            }

            let response = try promptForRelatedDeletion(related, index: index, total: relatedDeletions.count)

            switch response {
            case .yes:
                requests.append(DeletionRequest.fromRelatedDeletion(related))
            case .all:
                deleteAll = true
                requests.append(DeletionRequest.fromRelatedDeletion(related))
            case .quit:
                return requests
            default:
                continue
            }
        }

        return requests
    }

    private func promptForRelatedDeletion(_ related: RelatedDeletion, index: Int, total: Int) throws -> InteractiveResponse {
        while true {
            print("\n" + "Related code \(index + 1) of \(total)".teal)
            print("Description: ".subtext0 + related.description.yellow)
            print("File: ".subtext0 + "\(related.filePath):\(related.lineRange.lowerBound)".sky)
            print("")

            displayCodeSnippet(sourceText: related.sourceSnippet, startLine: related.lineRange.lowerBound, endLine: related.lineRange.upperBound)

            printOptions(for: "related code", displayingLineRange: false)

            let response = parseCommonResponse(inputProvider.readLine())

            switch response {
            case .yes:
                print("Marked for deletion.".green)
                return .yes
            case .no:
                print("Skipped.".yellow)
                return .no
            case .all:
                print("Marking this and all remaining related code for deletion.".green)
                return .all
            case .quit:
                print("Skipping all remaining related code.".yellow)
                return .quit
            case .openXcode:
                handleEditorOpening(filePath: related.filePath, lineNumber: related.lineRange.lowerBound, editor: .xcode)
                continue
            case .openZed:
                handleEditorOpening(filePath: related.filePath, lineNumber: related.lineRange.lowerBound, editor: .zed)
                continue
            default:
                continue
            }
        }
    }

    private func displayCodeSnippet(sourceText: String, startLine: Int, endLine: Int) {
        let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        let lineNumberWidth = max(String(endLine).count, 3)

        for (offset, line) in lines.enumerated() {
            let lineNumber = startLine + offset
            let lineNumberStr = String(format: "%\(lineNumberWidth)d", lineNumber)
            let lineContent = " \(lineNumberStr) │ \(line)"
            print(lineContent.red.bold)
        }
    }

    private func handleEditorOpening(filePath: String, lineNumber: Int, editor: Editor) {
        let editorName = editor == .xcode ? "Xcode" : "Zed"
        print("Opening in \(editorName)...".sky)
        try? editorOpener.open(filePath: filePath, lineNumber: lineNumber, editor: editor)
        print("Press Enter to continue...".overlay0, terminator: "")
        fflush(stdout)
        _ = inputProvider.readLine()
    }

    private func promptForItem(item: ReportItem, index: Int, total: Int) throws -> InteractiveResponse {
        while true {
            print("\n" + "─".repeated(60).overlay0)
            print("Declaration \(index + 1) of \(total)".teal.bold)
            print("Type: ".subtext0 + "\(item.type.rawValue)".yellow)
            print("Name: ".subtext0 + "\(item.name)".peach)
            print("File: ".subtext0 + "\(item.file):\(item.line)".sky)
            print("\n" + "─".repeated(60).overlay0)

            guard let extractedCode = try CodeExtractorVisitor.extractCode(for: item) else {
                print("Could not extract code for this declaration.".red)
                return .no
            }

            print("")
            displayCodeSnippet(sourceText: extractedCode.sourceText, startLine: extractedCode.startLine, endLine: extractedCode.endLine)

            printOptions(for: "declaration/s", displayingLineRange: true)

            let response = parseResponse(inputProvider.readLine())

            switch response {
            case .yes:
                print("Marked for deletion.".green)
                return .yes
            case .no:
                print("Skipped.".yellow)
                return .no
            case .all:
                print("Marking this and all remaining for deletion.".green)
                return .all
            case .quit:
                print("Skipping all remaining declarations.".yellow)
                return .quit
            case .openXcode:
                handleEditorOpening(filePath: item.file, lineNumber: item.line, editor: .xcode)
                continue
            case .openZed:
                handleEditorOpening(filePath: item.file, lineNumber: item.line, editor: .zed)
                continue
            case .lineRange(let lines):
                let validLines = lines.filter { (extractedCode.startLine...extractedCode.endLine).contains($0) }
                if validLines.isEmpty {
                    print("No valid lines in range. Valid lines: \(extractedCode.startLine)-\(extractedCode.endLine)".red)
                    continue
                }
                let sortedLines = validLines.sorted()
                print("Selected lines for deletion: \(sortedLines.map(String.init).joined(separator: ", "))".green)
                return .lineRange(validLines)
            }
        }
    }

    private func parseResponse(_ input: String?) -> InteractiveResponse {
        let commonResponse = parseCommonResponse(input)
        if commonResponse != .no || input?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return commonResponse
        }

        if let trimmedInput = input?.trimmingCharacters(in: .whitespacesAndNewlines),
            let lines = try? LineRangeParser.parse(trimmedInput) {
            return .lineRange(lines)
        }

        return .no
    }

    private func parseCommonResponse(_ input: String?) -> InteractiveResponse {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines), !input.isEmpty else {
            return .no
        }

        let lowercased = input.lowercased()

        switch lowercased {
        case "y", "yes":
            return .yes
        case "n", "no":
            return .no
        case "a", "all":
            return .all
        case "q", "quit":
            return .quit
        case "x", "xcode":
            return .openXcode
        case "z", "zed":
            return .openZed
        default:
            return .no
        }
    }

    private func printOptions(for step: String, displayingLineRange: Bool) {
        print("\n" + "Options:".subtext0)
        print("  [y]es".green + " - Delete this \(step)")
        print("  [n]o".yellow + " - Skip this \(step)")
        print("  [a]ll".peach + " - Delete all remaining \(step)")
        print("  [q]uit".red + " - Skip all remaining \(step)")
        print("  [x]code".sky + " - Open in Xcode")
        print("  [z]ed".sky + " - Open in Zed")
        if displayingLineRange {
            print("  " + "[line range]".mauve + " - Delete specific lines (e.g., '2-5 7 9-11')")
        }
        print("\nYour choice: ".lavender, terminator: "")
        fflush(stdout)
    }
}
