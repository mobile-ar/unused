import SwiftSyntax

/// Canonical symbol paths are independent of escaping and generic specialization.
/// Member signatures retain their full type spelling instead of using these paths.
enum SwiftTypeName {
    static func canonical(_ type: TypeSyntax) -> String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return normalized(identifier.name.identifierName)
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return canonical(member.baseType) + "." + normalized(member.name.identifierName)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return canonical(optional.wrappedType)
        }
        if let optional = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return canonical(optional.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return canonical(attributed.baseType)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            return canonical(existential.constraint)
        }
        if let metatype = type.as(MetatypeTypeSyntax.self) {
            return canonical(metatype.baseType)
        }
        if type.is(ArrayTypeSyntax.self) {
            return "Array"
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "Dictionary"
        }
        var depth = 0
        var text = ""
        for token in type.tokens(viewMode: .sourceAccurate) {
            if token.text == "<" {
                depth += 1
            } else if token.text == ">", depth > 0 {
                depth -= 1
            } else if depth == 0 {
                text += token.text
            }
        }
        return normalized(text)
    }

    static func normalized(_ name: String) -> String {
        let unescaped = name.replacing("`", with: "").replacing("::", with: ".")
        return unescaped.split(separator: ".", omittingEmptySubsequences: false).map { component in
            String(component.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
        }.joined(separator: ".")
    }

    static func inheritedNames(_ clause: InheritanceClauseSyntax?) -> Set<String> {
        guard let clause else { return [] }
        return clause.inheritedTypes.reduce(into: Set<String>()) { names, inherited in
            collectInheritedNames(inherited.type, into: &names)
        }
    }

    private static func collectInheritedNames(_ type: TypeSyntax, into names: inout Set<String>) {
        if type.is(SuppressedTypeSyntax.self) {
            return
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            for element in composition.elements {
                collectInheritedNames(element.type, into: &names)
            }
        } else if let attributed = type.as(AttributedTypeSyntax.self) {
            collectInheritedNames(attributed.baseType, into: &names)
        } else if let existential = type.as(SomeOrAnyTypeSyntax.self) {
            collectInheritedNames(existential.constraint, into: &names)
        } else if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) {
            names.insert(canonical(type))
        }
    }
}
