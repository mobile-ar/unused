//
//  Created by Fernando Romiti on 15/02/2026.
//

import SwiftSyntax

struct ImportInfo: Sendable {
    let moduleName: String
    let line: Int
    let filePath: String
}

struct ImportUsageResult: Sendable {
    let imports: [ImportInfo]
    let usedIdentifiers: Set<String>
    let typeInheritances: [String: Set<String>]
}

class ImportUsageVisitor: SyntaxVisitor {

    private(set) var imports: [ImportInfo] = []
    private(set) var usedIdentifiers = Set<String>()
    private(set) var typeInheritances: [String: Set<String>] = [:]
    private let filePath: String
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, sourceFile: SourceFileSyntax) {
        self.filePath = filePath
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        super.init(viewMode: .sourceAccurate)
    }

    var result: ImportUsageResult {
        ImportUsageResult(
            imports: imports,
            usedIdentifiers: usedIdentifiers,
            typeInheritances: typeInheritances
        )
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.text ?? node.path.trimmedDescription
        let location = node.startLocation(converter: sourceLocationConverter)
        imports.append(ImportInfo(
            moduleName: moduleName,
            line: location.line,
            filePath: filePath
        ))
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.text, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.text, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.text, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.text, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let identExpr = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            usedIdentifiers.insert(identExpr.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        if let identType = node.type.as(IdentifierTypeSyntax.self) {
            usedIdentifiers.insert(identType.name.text)
        }
        return .visitChildren
    }

    override func visit(_ node: TypeExprSyntax) -> SyntaxVisitorContinueKind {
        if let identType = node.type.as(IdentifierTypeSyntax.self) {
            usedIdentifiers.insert(identType.name.text)
        }
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if let attrName = node.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
            usedIdentifiers.insert(attrName)
        }
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.macroName.text)
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.macroName.text)
        return .visitChildren
    }

    private func collectInheritance(name: String, inheritanceClause: InheritanceClauseSyntax?) {
        guard let clause = inheritanceClause else { return }
        var inherited = Set<String>()
        for inheritedType in clause.inheritedTypes {
            if let typeName = inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text {
                inherited.insert(typeName)
            }
        }
        if !inherited.isEmpty {
            typeInheritances[name, default: []].formUnion(inherited)
        }
    }
}