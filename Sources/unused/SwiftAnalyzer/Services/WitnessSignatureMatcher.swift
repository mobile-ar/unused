import SwiftParser
import SwiftSyntax

struct WitnessSignatureMatcher {
    let graph: WitnessTypeGraph

    func matches(
        _ provider: MemberSignature, requirement: MemberSignature, providerOwner: String,
        protocolOwner: String
    ) -> Bool {
        guard SwiftTypeName.normalized(provider.name) == SwiftTypeName.normalized(requirement.name)
        else { return false }
        if requirement.kind == .associatedType {
            return provider.kind == .typealiasDeclaration || provider.kind == .type
                || provider.kind == .associatedType
        }
        guard provider.kind == requirement.kind, provider.isStatic == requirement.isStatic,
            provider.parameterLabels.map(SwiftTypeName.normalized)
                == requirement.parameterLabels.map(SwiftTypeName.normalized)
        else { return false }
        guard !provider.isAsync || requirement.isAsync,
            !provider.isThrowing || requirement.isThrowing
        else { return false }

        // Missing SDK type information and generic/associated types cannot safely disambiguate overloads.
        guard provider.parameterTypes.count == requirement.parameterTypes.count else { return true }
        let placeholders = Set(provider.genericParameters).union(requirement.genericParameters)
            .union(
                graph.definitions.values.flatMap { definition in
                    definition.requirements.filter { $0.kind == .associatedType }.map(\.name)
                }
            ).union(["Self"])
        for (providedType, requiredType) in zip(provider.parameterTypes, requirement.parameterTypes)
        {
            if let provided = concreteType(
                providedType, owner: providerOwner, placeholders: placeholders),
                let required = concreteType(
                    requiredType, owner: protocolOwner, placeholders: placeholders),
                provided != required
            {
                return false
            }
        }
        return true
    }

    private func concreteType(
        _ spelling: String, owner: String, placeholders: Set<String>
    ) -> String? {
        let source = Parser.parse(source: "typealias __UnusedWitnessType = \(spelling)")
        guard !source.hasError,
            let declaration = source.statements.first?.item.as(TypeAliasDeclSyntax.self)
        else { return nil }
        return concreteType(declaration.initializer.value, owner: owner, placeholders: placeholders)
    }

    private func concreteType(
        _ type: TypeSyntax, owner: String, placeholders: Set<String>
    ) -> String? {
        if let array = type.as(ArrayTypeSyntax.self) {
            return concreteType(array.element, owner: owner, placeholders: placeholders).map {
                "Swift.Array<\($0)>"
            }
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self),
            let key = concreteType(dictionary.key, owner: owner, placeholders: placeholders),
            let value = concreteType(dictionary.value, owner: owner, placeholders: placeholders)
        {
            return "Swift.Dictionary<\(key),\(value)>"
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return concreteType(optional.wrappedType, owner: owner, placeholders: placeholders).map
            { "Swift.Optional<\($0)>" }
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return concreteType(optional.wrappedType, owner: owner, placeholders: placeholders).map
            { "Swift.Optional<\($0)>" }
        }
        let arguments: GenericArgumentClauseSyntax?
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            arguments = identifier.genericArgumentClause
        } else if let member = type.as(MemberTypeSyntax.self) {
            // A specialized enclosing type needs generic substitution that is not available here.
            guard
                !member.baseType.tokens(viewMode: .sourceAccurate).contains(where: {
                    $0.text == "<"
                })
            else { return nil }
            arguments = member.genericArgumentClause
        } else {
            return nil
        }
        let name = SwiftTypeName.canonical(type)
        guard !name.split(separator: ".").contains(where: { placeholders.contains(String($0)) })
        else { return nil }
        let resolved = graph.resolveName(name, relativeTo: owner)
        guard graph.aliases[resolved] == nil else { return nil }
        let concreteName: String
        if graph.kinds[resolved] != nil, graph.kinds[resolved] != "protocol" {
            concreteName = resolved
        } else {
            let builtin = name.hasPrefix("Swift.") ? String(name.dropFirst(6)) : name
            let builtins: Set<String> = [
                "Bool", "String", "Substring", "Character", "Int", "Int8", "Int16", "Int32",
                "Int64", "Int128",
                "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "UInt128", "Float", "Double",
                "Float16", "Float80",
                "Void", "Never", "Array", "Dictionary", "Set", "Optional", "Result", "Range",
                "ClosedRange",
            ]
            guard builtins.contains(builtin) else { return nil }
            concreteName = "Swift." + builtin
        }
        guard let arguments else { return concreteName }
        var concreteArguments: [String] = []
        for argument in arguments.arguments {
            guard let argumentType = argument.argument.as(TypeSyntax.self),
                let value = concreteType(argumentType, owner: owner, placeholders: placeholders)
            else { return nil }
            concreteArguments.append(value)
        }
        return concreteName + "<" + concreteArguments.joined(separator: ",") + ">"
    }
}
