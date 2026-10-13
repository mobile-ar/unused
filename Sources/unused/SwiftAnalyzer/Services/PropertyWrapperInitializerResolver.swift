import SwiftParser
import SwiftSyntax

struct PropertyWrapperInitializerResolver {
    let graph: WitnessTypeGraph

    func resolve(
        candidates: [DeclarationIdentity], arguments: [(label: String, type: String?)],
        wrappedType: String?, suppliesWrappedValue: Bool, context: String,
        genericParameters: Set<String>
    ) -> Set<DeclarationIdentity> {
        var callArguments = arguments
        if suppliesWrappedValue && !arguments.contains(where: { $0.label == "wrappedValue" }) {
            callArguments.insert(("wrappedValue", wrappedType), at: 0)
        }
        let selected = matching(
            candidates, arguments: callArguments, context: context,
            genericParameters: genericParameters
        )
        if !selected.isEmpty || suppliesWrappedValue || !arguments.isEmpty { return selected }
        // Without init(), Swift's synthesized memberwise initialization can initialize
        // backing storage through init(wrappedValue:), even without a property default.
        return matching(
            candidates, arguments: [("wrappedValue", wrappedType)], context: context,
            genericParameters: genericParameters
        )
    }

    func typesAreCompatible(
        _ parameter: String, _ argument: String?, context: String,
        genericParameters: Set<String>
    ) -> Bool {
        guard let argument else { return true }
        func canonical(_ type: String) -> Set<String> {
            let normalized = SwiftTypeName.normalized(type)
            var name = normalized.hasPrefix("Swift.") ? String(normalized.dropFirst(6)) : normalized
            if normalized.first == "[", let collection = components(normalized) { name = collection.name }
            if name == "Self" { name = context }
            if name.hasPrefix("Self.") { name = context + "." + name.dropFirst(5) }
            return MemberOwnerResolver(graph: graph).resolve(
                name, relativeTo: context, includeInheritance: false
            ).names
        }
        let parameter = SwiftTypeName.normalized(parameter)
        let normalizedArgument = SwiftTypeName.normalized(argument)
        if parameter == normalizedArgument || parameter == "Any" || parameter == "AnyObject" { return true }
        let parameterRoot = WitnessTypeGraph.nominalName(parameter)
        if genericParameters.contains(parameterRoot) || genericParameters.contains(normalizedArgument)
            || genericParameters.contains(where: { parameter.hasPrefix($0 + ".") }) { return true }
        // Function and tuple conversions need semantic information unavailable here.
        if parameter.contains("->") || parameter.contains("(")
            || normalizedArgument.contains("->") || normalizedArgument.contains("(") { return true }
        if parameter.last == "?" {
            return typesAreCompatible(
                String(parameter.dropLast()), normalizedArgument.last == "?" ? String(normalizedArgument.dropLast()) : normalizedArgument,
                context: context, genericParameters: genericParameters
            )
        }
        let expected = canonical(parameter)
        let actual = canonical(normalizedArgument)
        if !expected.isDisjoint(with: actual) {
            if let expectedComponents = components(parameter), let actualComponents = components(normalizedArgument),
                !expectedComponents.arguments.isEmpty,
                expectedComponents.arguments.count == actualComponents.arguments.count {
                return zip(expectedComponents.arguments, actualComponents.arguments).allSatisfy {
                    typesAreCompatible($0.0, $0.1, context: context, genericParameters: genericParameters)
                }
            }
            return true
        }
        let providers = MemberOwnerResolver(graph: graph).resolve(normalizedArgument, relativeTo: context).names
        return !expected.isDisjoint(with: providers)
    }

    private func components(_ spelling: String) -> (name: String, arguments: [String])? {
        let tree = Parser.parse(source: "typealias WrapperArgument = " + spelling)
        guard let alias = tree.statements.first?.item.as(TypeAliasDeclSyntax.self), !alias.hasError else { return nil }
        let type = alias.initializer.value
        if let array = type.as(ArrayTypeSyntax.self) {
            return ("Array", [MemberSignature.typeSpelling(array.element)])
        }
        if let dictionary = type.as(DictionaryTypeSyntax.self) {
            return ("Dictionary", [MemberSignature.typeSpelling(dictionary.key), MemberSignature.typeSpelling(dictionary.value)])
        }
        let arguments = type.as(IdentifierTypeSyntax.self)?.genericArgumentClause?.arguments
            ?? type.as(MemberTypeSyntax.self)?.genericArgumentClause?.arguments
        let argumentTypes = arguments?.compactMap { $0.argument.as(TypeSyntax.self) } ?? []
        guard argumentTypes.count == (arguments?.count ?? 0) else { return nil }
        return (SwiftTypeName.canonical(type), argumentTypes.map(MemberSignature.typeSpelling))
    }

    private func matching(
        _ candidates: [DeclarationIdentity], arguments: [(label: String, type: String?)],
        context: String, genericParameters: Set<String>
    ) -> Set<DeclarationIdentity> {
        let call = CallUsage(kind: .initializer, argumentLabels: arguments.map(\.label))
        var matches: [(identity: DeclarationIdentity, omitted: Int, generic: Int, variadic: Int)] = []
        for identity in candidates where CallArgumentMatcher().matches(call, signature: identity.signature) {
            let signature = identity.signature
            let generics = genericParameters.union(signature.genericParameters)
            var bestOmitted: Int?
            func match(parameter: Int, argument: Int, omitted: Int) {
                if parameter == signature.parameterLabels.count {
                    if argument == arguments.count {
                        bestOmitted = min(bestOmitted ?? omitted, omitted)
                    }
                    return
                }
                if signature.variadicParameterIndices.contains(parameter) {
                    match(parameter: parameter + 1, argument: argument, omitted: omitted)
                    guard parameter < signature.parameterTypes.count else { return }
                    let spelling = signature.parameterTypes[parameter]
                    let elementType = spelling.hasSuffix("...") ? String(spelling.dropLast(3)) : spelling
                    var next = argument
                    while next < arguments.count,
                        arguments[next].label == (next == argument ? signature.parameterLabels[parameter] : "_"),
                        typesAreCompatible(elementType, arguments[next].type, context: context, genericParameters: generics) {
                        next += 1
                        match(parameter: parameter + 1, argument: next, omitted: omitted)
                    }
                    return
                }
                if signature.defaultParameterIndices.contains(parameter) {
                    match(parameter: parameter + 1, argument: argument, omitted: omitted + 1)
                }
                guard argument < arguments.count,
                    signature.parameterLabels[parameter] == arguments[argument].label,
                    parameter < signature.parameterTypes.count,
                    typesAreCompatible(
                        signature.parameterTypes[parameter], arguments[argument].type,
                        context: context, genericParameters: generics
                    ) else { return }
                match(parameter: parameter + 1, argument: argument + 1, omitted: omitted)
            }
            match(parameter: 0, argument: 0, omitted: 0)
            if let omitted = bestOmitted {
                // Only rank concrete-vs-generic overloads when every argument type is
                // known; unknown expressions cannot justify discarding a candidate.
                let generic = arguments.allSatisfy { $0.type != nil }
                    ? signature.parameterTypes.filter { generics.contains($0) }.count : 0
                matches.append((identity, omitted, generic, signature.variadicParameterIndices.count))
            }
        }
        let minimumDefaults = matches.map(\.omitted).min()
        matches = matches.filter { $0.omitted == minimumDefaults }
        let minimumGenerics = matches.map(\.generic).min()
        matches = matches.filter { $0.generic == minimumGenerics }
        let minimumVariadics = matches.map(\.variadic).min()
        return Set(matches.filter { $0.variadic == minimumVariadics }.map(\.identity))
    }
}
