import SwiftParser
import Testing
@testable import unused

struct TypeReferenceResolverTests {
    private func declarations(_ source: String, file: String = "File.swift", module: String? = nil) -> [Declaration] {
        let syntax = Parser.parse(source: source)
        let visitor = DeclarationVisitor(filePath: file, protocolRequirements: [:], sourceFile: syntax, moduleName: module)
        visitor.walk(syntax)
        return visitor.declarations
    }

    @Test func qualifiedReferenceProtectsOnlyItsNamespace() throws {
        let declarations = declarations("struct First { typealias Item = Int }; struct Second { typealias Item = String }")
        let result = TypeReferenceResolver(declarations: declarations).resolve([TypeReference(name: "First.Item")])
        let first = try #require(declarations.first { $0.name == "Item" && $0.parentType == "First" }?.identity)
        #expect(result == [first])
    }

    @Test func unqualifiedReferenceResolvesToTheClosestEnclosingType() throws {
        let declarations = declarations("typealias Item = Bool; struct Outer { typealias Item = Int; struct Inner {} }")
        let result = TypeReferenceResolver(declarations: declarations).resolve([
            TypeReference(name: "Item", enclosingTypePath: ["Outer", "Inner"])
        ])
        #expect(result == [try #require(declarations.first { $0.name == "Item" && $0.parentType == "Outer" }?.identity)])
    }

    @Test func explicitModuleNamesRemainSeparate() throws {
        let first = declarations("struct Item {}", file: "One.swift", module: "First")
        let second = declarations("struct Item {}", file: "Two.swift", module: "Second")
        let result = TypeReferenceResolver(declarations: first + second).resolve([TypeReference(name: "First.Item")])
        #expect(result == [try #require(first.first?.identity)])
    }

    @Test func localAliasesRequireMatchingFilesAndVisibleScopes() throws {
        let declarations = declarations("struct Owner { func run() { typealias Item = Int } }")
        let identity = try #require(declarations.first { $0.name == "Item" }?.identity)
        let resolver = TypeReferenceResolver(declarations: declarations)
        let visible = TypeReference(name: "Item", enclosingTypePath: ["Owner"], lexicalScope: identity.lexicalScope, file: "File.swift")
        #expect(resolver.resolve([visible]) == [identity])
        var wrongFile = visible
        wrongFile.file = "Other.swift"
        #expect(resolver.resolve([wrongFile]).isEmpty)
        #expect(resolver.resolve([TypeReference(name: "Item", enclosingTypePath: ["Owner"], file: "File.swift")]).isEmpty)
    }

    @Test func missingReferencesAndDeclarationsWithoutIdentityAreNotGuessed() {
        let declaration = Declaration(name: "Item", type: .typealias, file: "File.swift", line: 1, exclusionReason: .none, parentType: nil)
        #expect(TypeReferenceResolver(declarations: [declaration]).resolve([TypeReference(name: "Item")]).isEmpty)
        #expect(TypeReferenceResolver(declarations: declarations("struct Item {}" )).resolve([TypeReference(name: "Missing")]).isEmpty)
    }
}
