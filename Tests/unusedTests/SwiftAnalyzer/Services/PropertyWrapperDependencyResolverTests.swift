import SwiftSyntax
import Testing
@testable import unused

struct PropertyWrapperDependencyResolverTests {
    @Test
    func appliedWrapperProtectsExactTypeBindingAndInitializerIdentities() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var unrelated = 0, wrappedValue: Int
                var projectedValue: String { "projection" }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                init(wrappedValue: String) { self.wrappedValue = 0 }
                init(other: Int) { wrappedValue = other }
                init() { wrappedValue = 0 }
                func wrappedValue(_ argument: Int) {}
            }
            struct Model { @Box var value: Int = 1 }
            """])
        let used = fixture.resolve()
        let wrapped = try fixture.identity("Box", "wrappedValue", kind: .property)
        let initializer = try fixture.identity("Box", "init", labels: ["wrappedValue"], types: ["Int"])
        #expect(used == [try fixture.identity(nil, "Box"), wrapped, initializer])
        let file = try #require(fixture.parsedFiles.first)
        let inventory = PropertyWrapperSyntaxInventory()
        inventory.walk(file.sourceFile)
        #expect(inventory.nodes[wrapped.offset]?.is(PatternBindingSyntax.self) == true)
        #expect(inventory.nodes[initializer.offset]?.is(InitializerDeclSyntax.self) == true)
        #expect(inventory.nodes[try fixture.identity(nil, "Box").offset]?.is(StructDeclSyntax.self) == true)
    }

    @Test
    func noValueInitializationUsesOnlyApplicableDefaultInitializer() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Defaulted {
                var wrappedValue: Int
                init() { wrappedValue = 0 }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                init(unrelated: String = "") { wrappedValue = 0 }
                init(required: Int) { wrappedValue = required }
            }
            struct Model { @Defaulted var value: Int }
            """])
        #expect(fixture.hooks("Defaulted", in: fixture.resolve()) == [
            try fixture.identity("Defaulted", "wrappedValue"),
            try fixture.identity("Defaulted", "init", labels: [])
        ])
    }

    @Test
    func synthesizedMemberwiseInitializationUsesWrappedValueWithoutPropertyDefault() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Deferred {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                init(other: String) { wrappedValue = 0 }
            }
            struct Model { @Deferred var value: Int }
            """])
        #expect(fixture.hooks("Deferred", in: fixture.resolve()) == [
            try fixture.identity("Deferred", "wrappedValue"),
            try fixture.identity("Deferred", "init", labels: ["wrappedValue"])
        ])
    }

    @Test
    func attributeArgumentsAndDefaultsDoNotProtectUnrelatedOverloads() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Limited {
                var wrappedValue: Int
                init(wrappedValue: Int, limit: Int, enabled: Bool = true) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, limit: String, enabled: Bool = true) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, other: Int) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int, limit: Int, required: Int) { self.wrappedValue = wrappedValue }
                init(limit: Int) { wrappedValue = limit }
            }
            struct Model { @Limited(limit: 10) var value = 1 }
            """])
        #expect(fixture.hooks("Limited", in: fixture.resolve()) == [
            try fixture.identity("Limited", "wrappedValue"),
            try fixture.identity("Limited", "init", labels: ["wrappedValue", "limit", "enabled"],
                                 types: ["Int", "Int", "Bool"])
        ])
    }

    @Test
    func attributeOnlyAndExplicitWrappedValueInitializationRespectCallShape() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct AttributeOnly {
                var wrappedValue: Int
                init(count: Int, enabled: Bool = true) { wrappedValue = count }
                init(wrappedValue: Int, count: Int) { self.wrappedValue = wrappedValue }
                init() { wrappedValue = 0 }
            }
            @propertyWrapper struct Explicit {
                var wrappedValue: Int
                init(wrappedValue: Int, count: Int = 0) { self.wrappedValue = wrappedValue }
                init() { wrappedValue = 0 }
            }
            struct Model {
                @AttributeOnly(count: 2) var first: Int
                @Explicit(wrappedValue: 3) var second: Int
            }
            """])
        let used = fixture.resolve()
        #expect(fixture.hooks("AttributeOnly", in: used) == [
            try fixture.identity("AttributeOnly", "wrappedValue"),
            try fixture.identity("AttributeOnly", "init", labels: ["count", "enabled"])
        ])
        #expect(fixture.hooks("Explicit", in: used) == [
            try fixture.identity("Explicit", "wrappedValue"),
            try fixture.identity("Explicit", "init", labels: ["wrappedValue", "count"])
        ])
    }

    @Test
    func nestedQualifiedAndAliasedWrappersResolveAcrossFilesAndExtensions() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Wrapper.swift": """
                struct Namespace {
                    @propertyWrapper struct Box<T> {
                        var wrappedValue: T
                        init(wrappedValue: T) { self.wrappedValue = wrappedValue }
                        init(unrelated: T) { wrappedValue = unrelated }
                    }
                }
                @propertyWrapper struct Box {
                    var wrappedValue: Int
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                """,
            "Hooks.swift": """
                extension Namespace.Box { var projectedValue: T { wrappedValue } }
                """,
            "Model.swift": """
                typealias Scope = Namespace
                typealias Alias<T> = Scope.Box<T>
                struct Model {
                    @Alias var first = 1
                    @Scope.Box var second = 2
                    @Namespace.Box var third = 3
                    func projection() -> Int { $first }
                }
                """
        ])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Namespace", "Box")))
        #expect(fixture.hooks("Namespace.Box", in: used) == [
            try fixture.identity("Namespace.Box", "wrappedValue"),
            try fixture.identity("Namespace.Box", "projectedValue"),
            try fixture.identity("Namespace.Box", "init", labels: ["wrappedValue"])
        ])
        #expect(fixture.hooks("Box", in: used).isEmpty)
        #expect(!used.contains(try fixture.identity(nil, "Box")))
    }

    @Test
    func moduleQualificationIsResolvedWithoutChangingUnqualifiedGraph() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Example.Box var value = 1 }
            """], moduleName: "Example")
        #expect(fixture.hooks("Box", in: fixture.resolve()) == [
            try fixture.identity("Box", "wrappedValue"),
            try fixture.identity("Box", "init", labels: ["wrappedValue"])
        ])
    }

    @Test
    func unappliedWrappersAndNonWrapperAttributesDoNotKeepHooks() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Unapplied {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct NotAWrapper {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Model { @NotAWrapper var value = 1 }
            """])
        #expect(fixture.resolve().isEmpty)
        #expect(PropertyWrapperDependencyResolver(declarations: [], parsedFiles: [], graph: fixture.graph).resolve().isEmpty)
    }

    @Test
    func lexicalWrapperNameSelectsNestedWrapperNotSameNamedTopLevelType() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Namespace {
                @propertyWrapper struct Box {
                    var wrappedValue: Int
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                @Box var value = 1
            }
            """])
        let used = fixture.resolve()
        #expect(fixture.hooks("Box", in: used).isEmpty)
        #expect(fixture.hooks("Namespace.Box", in: used).count == 2)
    }

    @Test
    func composedWrappersProtectOnlyOutermostProjection() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Inner {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            @propertyWrapper struct Outer {
                var wrappedValue: Inner
                var projectedValue: Int { wrappedValue.wrappedValue }
                init(wrappedValue: Inner) { self.wrappedValue = wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = Inner(wrappedValue: wrappedValue) }
            }
            struct Model {
                @Outer @Inner var value = 1
                func projection() -> Int { $value }
            }
            """])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Outer", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Inner", "projectedValue")))
        #expect(used.contains(try fixture.identity("Outer", "init", labels: ["wrappedValue"], types: ["Inner"])))
        #expect(!used.contains(try fixture.identity("Outer", "init", labels: ["wrappedValue"], types: ["Int"])))
        #expect(used.contains(try fixture.identity("Model", "value")))
    }

    @Test
    func sameNamedLocalWrapperInAnotherFunctionIsNotApplied() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            func first() {
                @propertyWrapper struct Box {
                    var wrappedValue: Int
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                @Box var value = 1
            }
            func second() {
                @propertyWrapper struct Box {
                    var wrappedValue: Int
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
            }
            """])
        let used = fixture.resolve()
        let scope = try fixture.identity(nil, "first").offset
        #expect(used.count == 3)
        #expect(used.allSatisfy { $0.lexicalScope.first == scope })
    }

    @Test
    func wrappedTypeAnnotationResolvesInApplicationNamespaceNotWrapperNamespace() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            struct Library {
                struct Value {}
                @propertyWrapper struct Box {
                    var wrappedValue: Client.Value
                    init(wrappedValue: Value) { fatalError() }
                    init(wrappedValue: Client.Value) { self.wrappedValue = wrappedValue }
                }
            }
            struct Client {
                struct Value {}
                @Library.Box var value: Value = Value()
            }
            """])
        #expect(fixture.resolve().filter { $0.signature.kind == .initializer } == [
            try fixture.identity("Library.Box", "init", labels: ["wrappedValue"], types: ["Client.Value"])
        ])
    }
}
