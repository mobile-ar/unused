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
    private(set) var protocolExtensionUsedMembers: [String: Set<String>] = [:]
    private(set) var protocolDefinitions: [String: ProtocolDefinition] = [:]
    private(set) var typeInheritance: [String: Set<String>] = [:]
    private(set) var typeKinds: [String: String] = [:]
    private(set) var typeAliases: [String: Set<String>] = [:]

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    var result: ProtocolVisitorResult {
        ProtocolVisitorResult(
            protocolRequirements: protocolRequirements,
            protocolInheritance: protocolInheritance,
            projectDefinedProtocols: projectDefinedProtocols,
            importedModules: importedModules,
            conformedProtocols: conformedProtocols,
            protocolExtensionUsedMembers: protocolExtensionUsedMembers,
            protocolDefinitions: protocolDefinitions,
            typeInheritance: typeInheritance,
            typeKinds: typeKinds,
            typeAliases: typeAliases
        )
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.first?.name.identifierName ?? node.path.trimmedDescription
        importedModules.insert(moduleName)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SourceProtocolNameContext.qualified(node.name.identifierName, at: node)
        let requirements = ProtocolRequirementCollector.requirements(in: node)
        let parents = SwiftTypeName.inheritedNames(node.inheritanceClause)
        projectDefinedProtocols.insert(name)
        protocolRequirements[name, default: []].formUnion(requirements.map(\.name))
        if !parents.isEmpty {
            protocolInheritance[name, default: []].formUnion(parents)
        }
        var definition = protocolDefinitions[name] ?? ProtocolDefinition(name: name)
        definition.requirements.formUnion(requirements)
        definition.inheritedTypes.formUnion(parents)
        definition.isComplete = definition.isComplete && !node.hasError
        protocolDefinitions[name] = definition
        collectType(name: name, kind: "protocol", inheritedTypes: parents)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(
            name: SourceProtocolNameContext.qualified(node.name.identifierName, at: node),
            kind: "class", inheritedTypes: SwiftTypeName.inheritedNames(node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(
            name: SourceProtocolNameContext.qualified(node.name.identifierName, at: node),
            kind: "struct", inheritedTypes: SwiftTypeName.inheritedNames(node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(
            name: SourceProtocolNameContext.qualified(node.name.identifierName, at: node),
            kind: "enum", inheritedTypes: SwiftTypeName.inheritedNames(node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectType(
            name: SourceProtocolNameContext.qualified(node.name.identifierName, at: node),
            kind: "actor", inheritedTypes: SwiftTypeName.inheritedNames(node.inheritanceClause)
        )
        return .visitChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SourceProtocolNameContext.qualified(node.name.identifierName, at: node)
        typeAliases[name, default: []].formUnion(
            SourceProtocolNameContext.aliasTargets(in: node.initializer.value))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = SourceProtocolNameContext.qualified(
            SwiftTypeName.canonical(node.extendedType), at: node)
        let parents = SwiftTypeName.inheritedNames(node.inheritanceClause)
        typeInheritance[name, default: []].formUnion(parents)
        conformedProtocols.formUnion(parents)

        // Filtering requires the globally merged definitions, not this file's traversal order.
        let bodyVisitor = ProtocolExtensionBodyVisitor(viewMode: .sourceAccurate)
        bodyVisitor.walk(node.memberBlock)
        if !bodyVisitor.referencedMembers.isEmpty {
            protocolExtensionUsedMembers[name, default: []].formUnion(
                bodyVisitor.referencedMembers.map { SwiftTypeName.normalized($0) }
            )
        }
        return .visitChildren
    }

    private func collectType(name: String, kind: String, inheritedTypes: Set<String>) {
        typeKinds[name] = kind
        typeInheritance[name, default: []].formUnion(inheritedTypes)
        conformedProtocols.formUnion(inheritedTypes)
    }
}
