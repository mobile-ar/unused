import Testing
@testable import unused

struct PropertyWrapperInitializerResolverTests {
    @Test
    func exactNonGenericOverloadWinsOverGenericAndDefaultedAlternatives() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                init<T>(wrappedValue: T) { self.wrappedValue = 0 }
                init(wrappedValue: Int, extra: Int = 0) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Box var value = 1 }
            """])
        #expect(fixture.resolve().filter { $0.signature.kind == .initializer } == [
            try fixture.identity("Box", "init", labels: ["wrappedValue"], types: ["Int"])
        ])
    }

    @Test
    func variadicAttributeArgumentsAreMatchedWithoutKeepingWrongElementType() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int, values: Int...) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, values: String...) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, unrelated: Int...) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Box(values: 1, 2, 3) var value = 0 }
            """])
        #expect(fixture.resolve().filter { $0.signature.kind == .initializer } == [
            try fixture.identity("Box", "init", labels: ["wrappedValue", "values"], types: ["Int", "Int..."])
        ])
    }

    @Test
    func unknownExpressionsKeepOnlyLabelCompatibleCandidates() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box<T> {
                var wrappedValue: T
                init(wrappedValue: Int) { fatalError() }
                init(wrappedValue: String) { fatalError() }
                init(unrelated: Bool) { fatalError() }
            }
            struct Model { @Box var value = unknownFactory() }
            """])
        // Factory return types are not resolved by the syntax-only argument matcher.
        let resolver = PropertyWrapperInitializerResolver(graph: fixture.graph)
        let integer = try fixture.identity("Box", "init", labels: ["wrappedValue"], types: ["Int"])
        let string = try fixture.identity("Box", "init", labels: ["wrappedValue"], types: ["String"])
        let unrelated = try fixture.identity("Box", "init", labels: ["unrelated"])
        #expect(resolver.resolve(candidates: [integer, string, unrelated], arguments: [], wrappedType: nil,
                                 suppliesWrappedValue: true, context: "Box", genericParameters: []) == [integer, string])
        let initializers: Set<DeclarationIdentity> = fixture.resolve().filter { $0.signature.kind == .initializer }
        #expect(initializers == [integer, string])
    }

    @Test
    func typeCompatibilityResolvesSelfAliasesInheritanceAndOptionalPromotion() {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            class Base {}
            class Child: Base {}
            struct Box<T> {}
            struct Other<T> {}
            typealias Alias = Box<Int>
            """])
        let resolver = PropertyWrapperInitializerResolver(graph: fixture.graph)
        #expect(resolver.typesAreCompatible("Self", "Alias", context: "Box", genericParameters: []))
        #expect(resolver.typesAreCompatible("Base", "Child", context: "Box", genericParameters: []))
        #expect(resolver.typesAreCompatible("Int?", "Swift.Int", context: "Box", genericParameters: []))
        #expect(resolver.typesAreCompatible("T", "String", context: "Box", genericParameters: ["T"]))
        #expect(resolver.typesAreCompatible("T.Element", "Int", context: "Box", genericParameters: ["T"]))
        #expect(!resolver.typesAreCompatible("Other<Int>", "Box<Int>", context: "Box", genericParameters: []))
        #expect(!resolver.typesAreCompatible("String", "Int", context: "Box", genericParameters: []))
        #expect(!resolver.typesAreCompatible("Box<String>", "Box<Int>", context: "Box", genericParameters: []))
        #expect(!resolver.typesAreCompatible("[String]", "[Int]", context: "Box", genericParameters: []))
        #expect(resolver.typesAreCompatible("[T]", "Array<Int>", context: "Box", genericParameters: ["T"]))
        #expect(!resolver.typesAreCompatible("[String: Bool]", "[String: Int]", context: "Box", genericParameters: []))
        #expect(resolver.typesAreCompatible("Int", nil, context: "Box", genericParameters: []))
    }
}
