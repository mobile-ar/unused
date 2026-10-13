import SwiftSyntax

struct PropertyWrapperEnclosingSubscriptResolver {
    let graph: WitnessTypeGraph

    func matches(
        _ node: SubscriptDeclSyntax, enclosingType: String, wrapperType: String,
        wrappedType: String?
    ) -> Bool {
        guard node.modifiers.contains(where: { $0.name.text == "static" }) else { return false }
        let parameters = Array(node.parameterClause.parameters)
        guard parameters.count == 3,
            parameters.map({ $0.firstName.identifierName }) == ["_enclosingInstance", "wrapped", "storage"],
            parameters.allSatisfy({ $0.secondName != nil && $0.ellipsis == nil }),
            let wrapped = keyPath(parameters[1].type), let storage = keyPath(parameters[2].type)
        else { return false }
        let genericNames = PropertyWrapperSyntaxContext.genericParameters(at: node)
        let matcher = PropertyWrapperInitializerResolver(graph: graph)
        let context = PropertyWrapperSyntaxContext.owner(at: node)
        let instance = MemberSignature.typeSpelling(parameters[0].type)
        guard matcher.typesAreCompatible(instance, enclosingType, context: context, genericParameters: genericNames),
            matcher.typesAreCompatible(wrapped.root, enclosingType, context: context, genericParameters: genericNames),
            matcher.typesAreCompatible(storage.root, enclosingType, context: context, genericParameters: genericNames),
            matcher.typesAreCompatible(wrapped.value, wrappedType, context: context, genericParameters: genericNames),
            matcher.typesAreCompatible(storage.value, wrapperType, context: context, genericParameters: genericNames),
            matcher.typesAreCompatible(MemberSignature.typeSpelling(node.returnClause.type), wrappedType,
                                       context: context, genericParameters: genericNames)
        else { return false }
        let enclosingOwners = MemberOwnerResolver(graph: graph).resolve(enclosingType).names
        func satisfies(_ constraint: TypeSyntax) -> Bool {
            SourceProtocolNameContext.aliasTargets(in: constraint).allSatisfy { name in
                if name == "AnyObject" || name == "Swift.AnyObject" { return true }
                return !MemberOwnerResolver(graph: graph).resolve(name, relativeTo: context, includeInheritance: false)
                    .names.isDisjoint(with: enclosingOwners)
            }
        }
        for parameter in node.genericParameterClause?.parameters ?? GenericParameterListSyntax([]) {
            if parameter.name.identifierName == instance, let constraint = parameter.inheritedType,
                !satisfies(constraint) { return false }
        }
        for requirement in node.genericWhereClause?.requirements ?? GenericRequirementListSyntax([]) {
            if let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self),
                MemberSignature.typeSpelling(conformance.leftType) == instance,
                !satisfies(conformance.rightType) { return false }
            if let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self),
                let leftType = sameType.leftType.as(TypeSyntax.self),
                let rightType = sameType.rightType.as(TypeSyntax.self),
                MemberSignature.typeSpelling(leftType) == instance,
                !matcher.typesAreCompatible(MemberSignature.typeSpelling(rightType), enclosingType,
                                           context: context, genericParameters: []) { return false }
        }
        return true
    }

    private func keyPath(_ type: TypeSyntax) -> (root: String, value: String)? {
        let name = SwiftTypeName.canonical(type).split(separator: ".").last.map(String.init)
        guard ["KeyPath", "WritableKeyPath", "ReferenceWritableKeyPath"].contains(name ?? "") else { return nil }
        let arguments = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments
            ?? type.as(MemberTypeSyntax.self)?.genericArgumentClause?.arguments
        guard let arguments, arguments.count == 2 else { return nil }
        let types = arguments.compactMap { $0.argument.as(TypeSyntax.self) }
        guard types.count == 2 else { return nil }
        return (MemberSignature.typeSpelling(types[0]), MemberSignature.typeSpelling(types[1]))
    }
}
