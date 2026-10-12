import SwiftSyntax

/// Extracts nominal protocol references without mistaking generic arguments or constraints for parents.
enum SDKInterfaceTypeReferences {
    static func names(in type: TypeSyntax) -> Set<String>? {
        if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) {
            return [SwiftTypeName.canonical(type)]
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            var names = Set<String>()
            for element in composition.elements {
                names.formUnion(self.names(in: element.type) ?? [SwiftTypeName.canonical(element.type)])
            }
            return names
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self), existential.someOrAnySpecifier.text == "any" {
            return names(in: existential.constraint)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first, element.firstName == nil, element.secondName == nil {
            return names(in: element.type)
        }
        return nil
    }

    static func leafName(_ name: String) -> String {
        let nominalName = name.prefix { $0 != "<" }
        return String(nominalName.split(separator: ".").last ?? nominalName)
    }
}
