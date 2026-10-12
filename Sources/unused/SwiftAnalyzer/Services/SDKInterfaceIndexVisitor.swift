import SwiftSyntax

final class SDKInterfaceIndexVisitor: SyntaxVisitor {
    private(set) var index = SDKInterfaceIndex()
    private var scopes: [String] = []

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = scopedName(node.name.identifierName)
        var definition = ProtocolDefinition(name: name)
        definition.requirements = ProtocolRequirementCollector.requirements(in: node)
        definition.inheritedTypes = SwiftTypeName.inheritedNames(node.inheritanceClause)
        definition.isComplete = !node.hasError
        if let existing = index.protocols[name] {
            definition.requirements.formUnion(existing.requirements)
            definition.inheritedTypes.formUnion(existing.inheritedTypes)
            definition.isComplete = definition.isComplete && existing.isComplete
        }
        index.protocols[name] = definition
        enterType(node.name.identifierName, kind: "protocol", attributes: node.attributes)
        return .visitChildren
    }

    override func visitPost(_ node: ProtocolDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.identifierName, kind: "struct", attributes: node.attributes)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.identifierName, kind: "class", attributes: node.attributes)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.identifierName, kind: "enum", attributes: node.attributes)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterType(node.name.identifierName, kind: "actor", attributes: node.attributes)
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        scopes.append(SwiftTypeName.canonical(node.extendedType))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                index.exportedSymbols.insert(identifier.identifier.identifierName)
            }
        }
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements { index.exportedSymbols.insert(element.name.identifierName) }
        return .skipChildren
    }

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        let name = scopedName(node.name.identifierName)
        var alias = SDKInterfaceAlias(name: name)
        if let references = SDKInterfaceTypeReferences.names(in: node.initializer.value) {
            alias.referencedTypes = references
        } else {
            alias.isComplete = false
        }
        alias.isComplete = alias.isComplete && !node.hasError
        if let existing = index.aliases[name] {
            alias.referencedTypes.formUnion(existing.referencedTypes)
            alias.isComplete = alias.isComplete && existing.isComplete
        }
        index.aliases[name] = alias
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    private func scopedName(_ name: String) -> String {
        (scopes + [name]).joined(separator: ".")
    }

    private func enterType(_ name: String, kind: String, attributes: AttributeListSyntax) {
        index.typeKinds[scopedName(name)] = kind
        index.exportedSymbols.insert(name)
        if attributes.contains(where: { element in
            guard case .attribute(let attribute) = element else { return false }
            return SDKInterfaceTypeReferences.leafName(SwiftTypeName.canonical(attribute.attributeName)) == "propertyWrapper"
        }) {
            index.propertyWrappers.insert(name)
        }
        scopes.append(name)
    }
}
