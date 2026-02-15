//
//  Created by Fernando Romiti on 05/12/2025.
//

import SwiftSyntax

class ProtocolVisitor: SyntaxVisitor {

    private(set) var protocolRequirements: [String: Set<String>] = [:]
    private(set) var protocolInheritance: [String: Set<String>] = [:]
    private(set) var projectDefinedProtocols: Set<String> = []
    private(set) var importedModules: Set<String> = []
    private(set) var conformedProtocols: Set<String> = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    var result: ProtocolVisitorResult {
        ProtocolVisitorResult(
            protocolRequirements: protocolRequirements,
            protocolInheritance: protocolInheritance,
            projectDefinedProtocols: projectDefinedProtocols,
            importedModules: importedModules,
            conformedProtocols: conformedProtocols
        )
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.text ?? node.path.trimmedDescription
        importedModules.insert(moduleName)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let protocolName = node.name.identifierName
        var methods = Set<String>()

        projectDefinedProtocols.insert(protocolName)

        for member in node.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                methods.insert(funcDecl.name.identifierName)
            }
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        methods.insert(identifier.identifier.identifierName)
                    }
                }
            }
            if member.decl.is(SubscriptDeclSyntax.self) {
                methods.insert("subscript")
            }
            if member.decl.is(InitializerDeclSyntax.self) {
                methods.insert("init")
            }
        }

        protocolRequirements[protocolName] = methods

        let parents = extractProtocolParents(from: node.inheritanceClause)
        if !parents.isEmpty {
            protocolInheritance[protocolName] = parents
            conformedProtocols.formUnion(parents)
        }

        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectConformedProtocols(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectConformedProtocols(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectConformedProtocols(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectConformedProtocols(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectConformedProtocols(inheritanceClause: node.inheritanceClause)
        return .visitChildren
    }

    private func collectConformedProtocols(inheritanceClause: InheritanceClauseSyntax?) {
        guard let clause = inheritanceClause else { return }

        for inherited in clause.inheritedTypes {
            if let typeName = inherited.type.as(IdentifierTypeSyntax.self)?.name.text {
                conformedProtocols.insert(typeName)
            }
        }
    }

    private func extractProtocolParents(from inheritanceClause: InheritanceClauseSyntax?) -> Set<String> {
        guard let clause = inheritanceClause else { return [] }

        var parents = Set<String>()
        for inherited in clause.inheritedTypes {
            if let typeName = inherited.type.as(IdentifierTypeSyntax.self)?.name.text {
                parents.insert(typeName)
            }
        }
        return parents
    }

}