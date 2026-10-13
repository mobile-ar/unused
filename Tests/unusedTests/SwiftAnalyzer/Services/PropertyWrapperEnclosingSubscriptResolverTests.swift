import SwiftSyntax
import Testing
@testable import unused

struct PropertyWrapperEnclosingSubscriptResolverTests {
    @Test
    func appliedClassKeepsOnlyApplicableEnclosingInstanceSubscript() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> Int { get { 0 } set {} }
                static subscript(
                    _enclosingInstance owner: Other,
                    wrapped keyPath: ReferenceWritableKeyPath<Other, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Other, Box>
                ) -> Int { get { 0 } set {} }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, String>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> String { "" }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Different>
                ) -> Int { 0 }
                subscript(index: Int) -> Int { wrappedValue }
                static subscript(index: String) -> Int { 0 }
            }
            struct Different {}
            class Other {}
            class Model { @Box var value = 1 }
            """])
        let used = fixture.resolve()
        let subscriptIdentity = try fixture.identity("Box", "subscript",
            types: ["Owner", "ReferenceWritableKeyPath<Owner,Int>", "ReferenceWritableKeyPath<Owner,Box>"])
        #expect(used.filter { $0.signature.kind == .subscript } == [subscriptIdentity])
        let inventory = PropertyWrapperSyntaxInventory()
        inventory.walk(try #require(fixture.parsedFiles.first).sourceFile)
        #expect(inventory.nodes[subscriptIdentity.offset]?.is(SubscriptDeclSyntax.self) == true)
    }

    @Test
    func structAndStaticApplicationsDoNotUseEnclosingInstanceHook() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> Int { get { 0 } set {} }
            }
            struct Model { @Box var value = 1 }
            class StaticModel { @Box static var value = 1 }
            """])
        #expect(fixture.resolve().filter { $0.signature.kind == .subscript }.isEmpty)
    }

    @Test
    func enclosingInstanceConstraintsExcludeUnrelatedClassOverload() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            class Base {}
            class Other {}
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                static subscript<Owner: Base>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> Int { get { 0 } set {} }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> Int where Owner: Other { get { 0 } set {} }
            }
            class Model: Base { @Box var value = 1 }
            """])
        let used = fixture.resolve()
        let retained = used.filter { $0.signature.kind == .subscript }
        #expect(retained.count == 1)
        let identity = try #require(retained.first)
        let inventory = PropertyWrapperSyntaxInventory()
        inventory.walk(try #require(fixture.parsedFiles.first).sourceFile)
        let node = try #require(inventory.nodes[identity.offset]?.as(SubscriptDeclSyntax.self))
        #expect(node.genericWhereClause == nil)
        #expect(node.genericParameterClause?.parameters.first?.inheritedType?.trimmedDescription == "Base")
    }

    @Test
    func wrongLabelsNonStaticAndMalformedKeyPathShapesAreNotImplicitHooks() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner,
                    wrapped keyPath: ReferenceWritableKeyPath<Owner, Int>,
                    storage storageKeyPath: ReferenceWritableKeyPath<Owner, Box>
                ) -> Int { 0 }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner, unrelated keyPath: Int, storage storageKeyPath: Int
                ) -> Int { 0 }
                static subscript<Owner: AnyObject>(
                    _enclosingInstance owner: Owner, wrapped keyPath: Int, storage storageKeyPath: Int
                ) -> Int { 0 }
            }
            class Model { @Box var value = 1 }
            """])
        #expect(fixture.resolve().filter { $0.signature.kind == .subscript }.isEmpty)
    }
}
