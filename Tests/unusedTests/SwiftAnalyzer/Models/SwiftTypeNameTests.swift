import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct SwiftTypeNameTests {
    @Test(arguments: [
        ("`Namespace`<Int>.`Item`<String>", "Namespace.Item"),
        ("Namespace.Outer<Int>.Inner<String>", "Namespace.Outer.Inner"),
        ("Namespace.Item?", "Namespace.Item"),
        ("Namespace.Item!", "Namespace.Item"),
        ("Namespace.Item.Type", "Namespace.Item"),
        ("any Namespace.`Protocol`", "Namespace.Protocol"),
        ("some Namespace.`Protocol`", "Namespace.Protocol"),
        ("[Namespace.Item]", "Array"),
        ("[String: Namespace.Item]", "Dictionary")
    ])
    func canonicalNamesPreserveQualificationButNotSpecialization(_ spelling: String, _ expected: String) throws {
        #expect(SwiftTypeName.canonical(try parseType(spelling)) == expected)
    }

    @Test(arguments: [
        ("`Namespace`::`Item`", "Namespace.Item"),
        ("  `Outer` . `Inner`  ", "Outer.Inner"),
        ("Namespace.Item", "Namespace.Item"),
        ("`class`", "class")
    ])
    func normalizedNamesRemoveEscapingAndScopeSeparators(_ spelling: String, _ expected: String) {
        #expect(SwiftTypeName.normalized(spelling) == expected)
    }

    @Test
    func inheritedNamesIncludeCompositionsAndQualifiedTypesButNotSuppressedConstraints() throws {
        let source = Parser.parse(source: "struct Example: Namespace.Base<Int> & `Other`, ~Copyable, ~Escapable {}")
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        #expect(SwiftTypeName.inheritedNames(declaration.inheritanceClause) == ["Namespace.Base", "Other"])
        #expect(SwiftTypeName.inheritedNames(nil).isEmpty)
    }

    @Test
    func escapedProtocolIdentifiersAreNotMetatypeSuffixes() throws {
        let metatype = try parseType("Namespace.Protocol")
        let identifier = try parseType("Namespace.`Protocol`")
        #expect(metatype.is(MetatypeTypeSyntax.self))
        #expect(identifier.is(MemberTypeSyntax.self))
        #expect(SwiftTypeName.canonical(identifier) == "Namespace.Protocol")
    }

    @Test
    func repeatedInheritanceNamesAreDeduplicated() throws {
        let source = Parser.parse(source: "protocol Example: Namespace.Base, Namespace.Base, `Other` {}")
        let declaration = try #require(source.statements.first?.item.as(ProtocolDeclSyntax.self))
        #expect(SwiftTypeName.inheritedNames(declaration.inheritanceClause) == ["Namespace.Base", "Other"])
    }

    private func parseType(_ spelling: String) throws -> TypeSyntax {
        let source = Parser.parse(source: "typealias Example = \(spelling)")
        let declaration = try #require(source.statements.first?.item.as(TypeAliasDeclSyntax.self))
        return declaration.initializer.value
    }
}
