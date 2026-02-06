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

                let relatedDeletions = try await relatedCodeFinder.findRelatedCode(for: item)
                for related in relatedDeletions {
                    confirmedRequests.append(DeletionRequest.fromRelatedDeletion(related))
                }
                continue
            }

            let result = try promptForItem(item: item, index: index, total: items.count)

            switch result {
            case .yes:
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))

                let relatedDeletions = try await relatedCodeFinder.findRelatedCode(for: item)
                if !relatedDeletions.isEmpty {
                    let relatedRequests = try promptForRelatedDeletions(
                        relatedDeletions,
                        for: item,
                        deleteAll: &deleteAllRelated
                    )
                    confirmedRequests.append(contentsOf: relatedRequests)
                }
            case .no:
                continue
            case .all:
                deleteAllRemaining = true
                deleteAllRelated = true
                confirmedRequests.append(DeletionRequest(item: item, mode: .fullDeclaration))

                let relatedDeletions = try await relatedCodeFinder.findRelatedCode(for: item)
                for related in relatedDeletions {
                    confirmedRequests.append(DeletionRequest.fromRelatedDeletion(related))
                }
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

    private func promptForRelatedDeletions(
        _ relatedDeletions: [RelatedDeletion],
        for item: ReportItem,
        deleteAll: inout Bool
    ) throws -> [DeletionRequest] {
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

            displayRelatedCodeSnippet(related)

            print("\n" + "Options:".subtext0)
            print("  [y]es".green + " - Delete this related code")
            print("  [n]o".yellow + " - Skip this related code")
            print("  [a]ll".peach + " - Delete all remaining related code")
            print("  [q]uit".red + " - Skip all remaining related code")
            print("  [x]code".sky + " - Open in Xcode")
            print("  [z]ed".sky + " - Open in Zed")
            print("\nYour choice: ".lavender, terminator: "")
            fflush(stdout)

            let response = parseRelatedResponse(inputProvider.readLine())

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
                print("Opening in Xcode...".sky)
                try? editorOpener.open(filePath: related.filePath, lineNumber: related.lineRange.lowerBound, editor: .xcode)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
                continue
            case .openZed:
                print("Opening in Zed...".sky)
                try? editorOpener.open(filePath: related.filePath, lineNumber: related.lineRange.lowerBound, editor: .zed)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
                continue
            default:
                continue
            }
        }
    }

    private func displayRelatedCodeSnippet(_ related: RelatedDeletion) {
        let lines = related.sourceSnippet.split(separator: "\n", omittingEmptySubsequences: false)
        let lineNumberWidth = max(String(related.lineRange.upperBound).count, 3)

        for (offset, line) in lines.enumerated() {
            let lineNumber = related.lineRange.lowerBound + offset
            let lineNumberStr = String(format: "%\(lineNumberWidth)d", lineNumber)
            let lineContent = " \(lineNumberStr) │ \(line)"
            print(lineContent.red.bold)
        }
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

            displayCodeWithLineNumbers(extractedCode)

            print("\n" + "Options:".subtext0)
            print("  [y]es".green + " - Delete this declaration")
            print("  [n]o".yellow + " - Skip this declaration")
            print("  [a]ll".peach + " - Delete all remaining declarations")
            print("  [q]uit".red + " - Skip all remaining declarations")
            print("  [x]code".sky + " - Open in Xcode")
            print("  [z]ed".sky + " - Open in Zed")
            print("  " + "[line range]".mauve + " - Delete specific lines (e.g., '2-5 7 9-11')")
            print("\nYour choice: ".lavender, terminator: "")
            fflush(stdout)

            let response = parseResponse(inputProvider.readLine(), validLineRange: extractedCode.startLine...extractedCode.endLine)

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
                print("Opening in Xcode...".sky)
                try? editorOpener.open(filePath: item.file, lineNumber: item.line, editor: .xcode)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
                continue
            case .openZed:
                print("Opening in Zed...".sky)
                try? editorOpener.open(filePath: item.file, lineNumber: item.line, editor: .zed)
                print("Press Enter to continue...".overlay0, terminator: "")
                fflush(stdout)
                _ = inputProvider.readLine()
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

    private func displayCodeWithLineNumbers(_ code: ExtractedCode) {
        let lines = code.sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        let lineNumberWidth = max(String(code.endLine).count, 3)

        print("")
        for (offset, line) in lines.enumerated() {
            let lineNumber = code.startLine + offset
            let lineNumberStr = String(format: "%\(lineNumberWidth)d", lineNumber)
            let lineContent = " \(lineNumberStr) │ \(line)"
            print(lineContent.red.bold)
        }
    }

    private func parseResponse(_ input: String?, validLineRange: ClosedRange<Int>) -> InteractiveResponse {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
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
            if let lines = try? LineRangeParser.parse(input) {
                return .lineRange(lines)
            }
            return .no
        }
    }

    private func parseRelatedResponse(_ input: String?) -> InteractiveResponse {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
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
}