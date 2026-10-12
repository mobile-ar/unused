import SwiftSyntax

enum SourceProtocolNameContext {
    static func qualified(_ name: String, at node: some SyntaxProtocol) -> String {
        let scope = enclosingNames(of: node).joined(separator: ".")
        let normalized = SwiftTypeName.normalized(name)
        return scope.isEmpty ? normalized : "\(scope).\(normalized)"
    }

    private static func enclosingNames(of node: some SyntaxProtocol) -> [String] {
        var names: [String] = []
        var parent = node.parent
        while let current = parent {
            if let declaration = current.as(ClassDeclSyntax.self) {
                names.append(declaration.name.identifierName)
            } else if let declaration = current.as(StructDeclSyntax.self) {
                names.append(declaration.name.identifierName)
            } else if let declaration = current.as(EnumDeclSyntax.self) {
                names.append(declaration.name.identifierName)
            } else if let declaration = current.as(ActorDeclSyntax.self) {
                names.append(declaration.name.identifierName)
            } else if let declaration = current.as(ProtocolDeclSyntax.self) {
                names.append(declaration.name.identifierName)
            } else if let declaration = current.as(ExtensionDeclSyntax.self) {
                names.append(SwiftTypeName.canonical(declaration.extendedType))
            }
            parent = current.parent
        }
        return names.reversed()
    }

    static func aliasTargets(in type: TypeSyntax) -> Set<String> {
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.reduce(into: []) { result, element in
                result.formUnion(aliasTargets(in: element.type))
            }
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return aliasTargets(in: attributed.baseType)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return aliasTargets(in: existential.constraint)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
            let element = tuple.elements.first, element.firstName == nil
        {
            return aliasTargets(in: element.type)
        }
        return [SwiftTypeName.canonical(type)]
    }
}
