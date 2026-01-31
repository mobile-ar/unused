//
//  Created by Fernando Romiti on 01/02/2026.
//

import SwiftSyntax
import SwiftParser

struct ExtractedCode {
    let sourceText: String
    let startLine: Int
    let endLine: Int
}

final class CodeExtractorVisitor: SyntaxVisitor {

    private let target: DeletionTarget
    private let locationConverter: SourceLocationConverter
    private let sourceFile: SourceFileSyntax
    private(set) var extractedCode: ExtractedCode?

    init(target: DeletionTarget, sourceFile: SourceFileSyntax, fileName: String = "source.swift") {
        self.target = target
        self.sourceFile = sourceFile
        self.locationConverter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    private func getLineNumber(for node: some SyntaxProtocol) -> Int {
        let location = node.startLocation(converter: locationConverter)
        return location.line
    }

    private func getEndLineNumber(for node: some SyntaxProtocol) -> Int {
        let location = node.endLocation(converter: locationConverter)
        return location.line
    }

    private func getSourceAndLineRange(for node: some SyntaxProtocol) -> (sourceText: String, startLine: Int, endLine: Int) {
        let nodeStartLine = getLineNumber(for: node)
        let nodeEndLine = getEndLineNumber(for: node)

        // Get the raw description which includes leading trivia (comments, whitespace)
        let rawSource = node.description

        // Count newlines in the leading trivia, but exclude the first newline
        // which is just the line separator from the previous line (not part of this declaration)
        let leadingTrivia = node.leadingTrivia.description
        let triviaAfterFirstNewline: Substring
        if leadingTrivia.hasPrefix("\n") {
            triviaAfterFirstNewline = leadingTrivia.dropFirst()
        } else {
            triviaAfterFirstNewline = leadingTrivia[...]
        }
        let meaningfulLeadingNewlines = triviaAfterFirstNewline.filter { $0 == "\n" }.count

        // The start line includes the meaningful leading trivia (comments, etc.)
        let adjustedStartLine = nodeStartLine - meaningfulLeadingNewlines

        // Trim the leading newline (line separator) and trailing newlines from source text
        var sourceText = rawSource
        if sourceText.hasPrefix("\n") {
            sourceText.removeFirst()
        }
        while sourceText.hasSuffix("\n") {
            sourceText.removeLast()
        }

        return (sourceText, adjustedStartLine, nodeEndLine)
    }

    private func extractIfMatches(name: String, line: Int, type: DeclarationType, node: some SyntaxProtocol) {
        guard target.name == name && target.line == line && target.type == type else {
            return
        }

        let (sourceText, startLine, endLine) = getSourceAndLineRange(for: node)

        extractedCode = ExtractedCode(
            sourceText: sourceText,
            startLine: startLine,
            endLine: endLine
        )
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let lineNumber = getLineNumber(for: node)
        extractIfMatches(name: node.name.text, line: lineNumber, type: .function, node: node)
        return extractedCode == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let lineNumber = getLineNumber(for: node)
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                extractIfMatches(name: identifier.identifier.text, line: lineNumber, type: .variable, node: node)
                if extractedCode != nil {
                    return .skipChildren
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let lineNumber = getLineNumber(for: node)
        extractIfMatches(name: node.name.text, line: lineNumber, type: .class, node: node)
        return extractedCode == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let lineNumber = getLineNumber(for: node)
        extractIfMatches(name: node.name.text, line: lineNumber, type: .class, node: node)
        return extractedCode == nil ? .visitChildren : .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let lineNumber = getLineNumber(for: node)
        extractIfMatches(name: node.name.text, line: lineNumber, type: .class, node: node)
        return extractedCode == nil ? .visitChildren : .skipChildren
    }

    static func extractCode(for item: ReportItem) throws -> ExtractedCode? {
        let source = try String(contentsOfFile: item.file, encoding: .utf8)
        let sourceFile = Parser.parse(source: source)
        let target = DeletionTarget(from: item)
        let visitor = CodeExtractorVisitor(target: target, sourceFile: sourceFile, fileName: item.file)
        visitor.walk(sourceFile)
        return visitor.extractedCode
    }
}
