//
//  Created by Fernando Romiti on 15/02/2026.
//

import SwiftSyntax

final class ImportUsageVisitor: SyntaxVisitor {
    private(set) var imports: [ImportInfo] = []
    private(set) var usedIdentifiers = Set<String>()
    private(set) var typeInheritances: [String: Set<String>] = [:]
    private(set) var qualifiedReferences: Set<String> = []
    private(set) var uncertainties: Set<ImportUsageUncertainty> = []
    private let filePath: String
    private let sourceLocationConverter: SourceLocationConverter

    init(filePath: String, sourceFile: SourceFileSyntax) {
        self.filePath = filePath
        self.sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        self.uncertainties = sourceFile.hasError ? [.recoveredSyntax] : []
        super.init(viewMode: .sourceAccurate)
    }

    var result: ImportUsageResult {
        ImportUsageResult(
            imports: imports,
            usedIdentifiers: usedIdentifiers,
            typeInheritances: typeInheritances,
            qualifiedReferences: qualifiedReferences,
            uncertainties: uncertainties
        )
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.identifierName ?? node.path.trimmedDescription
        let location = node.startLocation(converter: sourceLocationConverter)
        let attributes = node.attributes.compactMap { element -> String? in
            guard case .attribute(let attribute) = element else { return nil }
            return SwiftTypeName.canonical(attribute.attributeName)
        }
        var importUncertainties: Set<ImportUsageUncertainty> = []
        if attributes.contains(where: { $0 != "_exported" }) {
            // Public interfaces need not contain testable, SPI or other restricted exports.
            importUncertainties.insert(.restrictedImport)
        }
        if node.importKindSpecifier == nil && node.path.count > 1 {
            importUncertainties.insert(.submoduleImport)
        }
        imports.append(ImportInfo(
            moduleName: moduleName,
            line: location.line,
            filePath: filePath,
            isReexported: attributes.contains("_exported"),
            uncertainties: importUncertainties
        ))
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.identifierName, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.identifierName, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.identifierName, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectInheritance(name: node.name.identifierName, inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.identifierName)
        return .visitChildren
    }

    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.name.identifierName)
        collectQualifiedReference(SwiftTypeName.canonical(TypeSyntax(node)))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.baseName.identifierName)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.identifierName)
        if let path = expressionPath(ExprSyntax(node)) {
            collectQualifiedReference(path)
        } else if node.base == nil {
            uncertainties.insert(.implicitMember)
        }
        return .visitChildren
    }

    override func visit(_ node: KeyPathPropertyComponentSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.declName.baseName.identifierName)
        return .visitChildren
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert("subscript")
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Constructor calls can resolve to an initializer supplied by an imported extension.
        usedIdentifiers.formUnion(["init", "callAsFunction"])
        return .visitChildren
    }

    override func visit(_ node: ExpressionSegmentSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert("appendInterpolation")
        return .visitChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(node.attributeName)
        usedIdentifiers.insert(SDKInterfaceTypeReferences.leafName(name))
        if name.contains(".") { collectQualifiedReference(name) }
        // Syntax alone cannot distinguish a custom attached macro or wrapper from a compiler attribute.
        uncertainties.insert(.attributeExpansion(name))
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        collectMacro(node.macroName.identifierName)
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectMacro(node.macroName.identifierName)
        return .visitChildren
    }

    override func visit(_ node: BinaryOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.identifierName)
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.identifierName)
        return .visitChildren
    }

    override func visit(_ node: PostfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        usedIdentifiers.insert(node.operator.identifierName)
        return .visitChildren
    }

    private func collectMacro(_ name: String) {
        usedIdentifiers.insert(name)
        // Generated references are not present in the unexpanded source tree.
        uncertainties.insert(.macroExpansion(name))
    }

    private func collectQualifiedReference(_ name: String) {
        qualifiedReferences.insert(name)
        usedIdentifiers.insert(name)
    }

    private func expressionPath(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.identifierName
        }
        if let member = expression.as(MemberAccessExprSyntax.self), let base = member.base,
           let prefix = expressionPath(base) {
            return prefix + "." + member.declName.baseName.identifierName
        }
        if let specialization = expression.as(GenericSpecializationExprSyntax.self) {
            return expressionPath(specialization.expression)
        }
        return nil
    }

    private func collectInheritance(name: String, inheritanceClause: InheritanceClauseSyntax?) {
        let inherited = SwiftTypeName.inheritedNames(inheritanceClause)
        if !inherited.isEmpty {
            // Preserve leaf names for the existing transitive graph while also retaining qualified paths.
            typeInheritances[name, default: []].formUnion(inherited)
            typeInheritances[name, default: []].formUnion(inherited.map(SDKInterfaceTypeReferences.leafName))
        }
    }
}
