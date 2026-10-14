import SwiftSyntax

final class SDKInterfaceIndexVisitor: SyntaxVisitor {
    private(set) var index = SDKInterfaceIndex()
    private var scopes: [String] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let moduleName = node.path.first?.name.identifierName {
            index.importedModules.insert(moduleName)
        }
        let isReexported = node.attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return SwiftTypeName.canonical(attribute.attributeName) == "_exported"
        }
        guard isReexported else { return .skipChildren }
        let path = node.path.map { $0.name.identifierName }.joined(separator: ".")
        if node.importKindSpecifier != nil || node.path.count != 1 {
            // Scoped imports and Clang submodules cannot be flattened as whole-module re-exports.
            index.symbolInventoryUncertainties.insert(.scopedReexport(path))
        }
        if let moduleName = node.path.first?.name.identifierName {
            index.reexportedModules.insert(moduleName)
        }
        return .skipChildren
    }

    override func visit(_ node: OperatorDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        return .skipChildren
    }

    override func visit(_ node: MacroDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        index.symbolInventoryUncertainties.insert(.macroExpansion)
        return .skipChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        index.symbolInventoryUncertainties.insert(.macroExpansion)
        return .skipChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        let name = SwiftTypeName.canonical(node.attributeName)
        switch name {
        case "available", "frozen", "inlinable", "usableFromInline", "_alwaysEmitIntoClient",
             "propertyWrapper", "resultBuilder", "attached", "freestanding":
            break
        case "_hasMissingDesignatedInitializers":
            index.symbolInventoryUncertainties.insert(.implicitExports)
        default:
            // Only known compiler annotations are exempt: an unknown attribute may generate exports.
            index.symbolInventoryUncertainties.insert(.attributeExpansion(name))
        }
        return .skipChildren
    }

    override func visit(_ node: PrecedenceGroupDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        // Precedence relationships are token references, not ordinary identifier/type uses.
        index.symbolInventoryUncertainties.insert(.unrepresentedDeclaration)
        return .skipChildren
    }

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
        if node.inheritanceClause != nil {
            // Retroactive conformances can make an import necessary without a named member use.
            index.symbolInventoryUncertainties.insert(.implicitExports)
        }
        scopes.append(SwiftTypeName.canonical(node.extendedType))
        return .visitChildren
    }

    override func visitPost(_ node: ExtensionDeclSyntax) { scopes.removeLast() }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert(node.name.identifierName)
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            collectBindingNames(binding.pattern)
        }
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: EnumCaseDeclSyntax) -> SyntaxVisitorContinueKind {
        for element in node.elements { index.exportedSymbols.insert(element.name.identifierName) }
        walk(node.attributes)
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
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert("init")
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        index.exportedSymbols.insert("subscript")
        walk(node.attributes)
        return .skipChildren
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    private func collectBindingNames(_ pattern: PatternSyntax) {
        if let identifier = pattern.as(IdentifierPatternSyntax.self) {
            index.exportedSymbols.insert(identifier.identifier.identifierName)
        } else if let tuple = pattern.as(TuplePatternSyntax.self) {
            for element in tuple.elements { collectBindingNames(element.pattern) }
        } else if let binding = pattern.as(ValueBindingPatternSyntax.self) {
            collectBindingNames(binding.pattern)
        } else if !pattern.is(WildcardPatternSyntax.self) {
            index.symbolInventoryUncertainties.insert(.unrepresentedDeclaration)
        }
    }

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
