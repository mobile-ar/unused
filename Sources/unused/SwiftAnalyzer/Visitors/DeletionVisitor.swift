//
//  Created by Fernando Romiti on 28/01/2026.
//

import SwiftSyntax
import SwiftParser

/// A syntax rewriter that removes specified declarations from Swift source code
final class DeletionVisitor: SyntaxRewriter {

    private let declarationsToDelete: Set<DeletionTarget>
    private let locationConverter: SourceLocationConverter
    private(set) var deletedCount: Int = 0

    init(targets: [DeletionTarget], sourceFile: SourceFileSyntax, fileName: String = "source.swift") {
        self.declarationsToDelete = Set(targets)
        self.locationConverter = SourceLocationConverter(fileName: fileName, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    private func shouldDelete(name: String, line: Int, type: DeclarationType) -> Bool {
        declarationsToDelete.contains(DeletionTarget(name: name, line: line, type: type))
    }

    private func getLineNumber(for node: some SyntaxProtocol) -> Int {
        let location = node.startLocation(converter: locationConverter)
        return location.line
    }

    private func shouldDeleteDeclaration(_ decl: DeclSyntax) -> Bool {
        if let funcDecl = decl.as(FunctionDeclSyntax.self) {
            let lineNumber = getLineNumber(for: funcDecl)
            if shouldDelete(name: funcDecl.name.text, line: lineNumber, type: .function) {
                deletedCount += 1
                return true
            }
        } else if let varDecl = decl.as(VariableDeclSyntax.self) {
            let lineNumber = getLineNumber(for: varDecl)
            for binding in varDecl.bindings {
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    if shouldDelete(name: identifier.identifier.text, line: lineNumber, type: .variable) {
                        deletedCount += 1
                        return true
                    }
                }
            }
        } else if let classDecl = decl.as(ClassDeclSyntax.self) {
            let lineNumber = getLineNumber(for: classDecl)
            if shouldDelete(name: classDecl.name.text, line: lineNumber, type: .class) {
                deletedCount += 1
                return true
            }
        } else if let structDecl = decl.as(StructDeclSyntax.self) {
            let lineNumber = getLineNumber(for: structDecl)
            if shouldDelete(name: structDecl.name.text, line: lineNumber, type: .class) {
                deletedCount += 1
                return true
            }
        } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
            let lineNumber = getLineNumber(for: enumDecl)
            if shouldDelete(name: enumDecl.name.text, line: lineNumber, type: .class) {
                deletedCount += 1
                return true
            }
        }
        return false
    }

    override func visit(_ node: CodeBlockItemListSyntax) -> CodeBlockItemListSyntax {
        var newItems: [CodeBlockItemSyntax] = []

        for item in node {
            var shouldKeep = true

            if let decl = item.item.as(DeclSyntax.self) {
                shouldKeep = !shouldDeleteDeclaration(decl)
            }

            if shouldKeep {
                let rewrittenItem = super.visit(item)
                newItems.append(rewrittenItem)
            }
        }

        return CodeBlockItemListSyntax(newItems)
    }

    override func visit(_ node: MemberBlockItemListSyntax) -> MemberBlockItemListSyntax {
        var newItems: [MemberBlockItemSyntax] = []

        for item in node {
            let shouldKeep = !shouldDeleteDeclaration(item.decl)

            if shouldKeep {
                let rewrittenItem = super.visit(item)
                newItems.append(rewrittenItem)
            }
        }

        return MemberBlockItemListSyntax(newItems)
    }
}

struct DeletionTarget: Hashable {
    let name: String
    let line: Int
    let type: DeclarationType
}

extension DeletionTarget {
    init(from item: ReportItem) {
        self.name = item.name
        self.line = item.line
        self.type = item.type
    }
}
