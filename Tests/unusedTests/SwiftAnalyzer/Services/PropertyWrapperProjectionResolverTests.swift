import Testing
@testable import unused

struct PropertyWrapperProjectionResolverTests {
    @Test
    func bareAndSelfProjectionUsesAreScopedToEnclosingOwner() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Used {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            @propertyWrapper struct Unused {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct First {
                @Used var value = 1
                func read() -> Int { $value + self.$value }
            }
            struct Second {
                @Unused var value = 2
                func read() -> Int { value }
            }
            """])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Used", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Unused", "projectedValue")))
        #expect(used.contains(try fixture.identity("First", "value")))
        #expect(!used.contains(try fixture.identity("Second", "value")))
    }

    @Test
    func typedReceiversAliasesAndConstructedLocalReceiversResolveAcrossFiles() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Wrapper.swift": """
                @propertyWrapper struct Used {
                    var wrappedValue: Int
                    var projectedValue: Int { wrappedValue }
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                @propertyWrapper struct Unused {
                    var wrappedValue: Int
                    var projectedValue: Int { wrappedValue }
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                struct First { @Used var value = 1 }
                struct Second { @Unused var value = 1 }
                """,
            "Use.swift": """
                typealias Alias = First
                func parameter(_ receiver: Alias) -> Int { receiver.$value }
                func local() -> Int {
                    let receiver = First()
                    return receiver.$value
                }
                func noProjection(_ receiver: Second) -> Int { receiver.value }
                """
        ])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Used", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Unused", "projectedValue")))
    }

    @Test
    func unknownAndShadowedReceiversDoNotKeepEverySameNamedProjection() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Box var value = 1 }
            func unresolved(_ receiver: External) { _ = receiver.$value }
            func shadowed() {
                let Model = unknownFactory()
                _ = Model.$value
            }
            func shorthandClosure() { _ = [1].map { $0 } }
            """])
        let used = fixture.resolve()
        #expect(!used.contains(try fixture.identity("Box", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Model", "value")))
    }

    @Test
    func localProjectionsDoNotLeakAcrossFunctionsOrNestedScopes() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Used {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            @propertyWrapper struct Unused {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            func first() {
                @Used var value = 1
                _ = $value
                if true {
                    @Unused var value = 2
                    _ = value
                }
            }
            func second() { @Unused var value = 3 }
            func unrelated() { _ = $value }
            """])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Used", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Unused", "projectedValue")))
        let locals = used.filter { $0.signature.name == "value" }
        #expect(locals.count == 1)
        #expect(locals.first?.lexicalScope.isEmpty == false)
    }

    @Test
    func extensionAndInheritedProjectionUsesSelectKnownProvider() throws {
        let fixture = PropertyWrapperResolverFixture.parse([
            "Model.swift": """
                @propertyWrapper struct Box {
                    var wrappedValue: Int
                    var projectedValue: Int { wrappedValue }
                    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
                }
                class Base { @Box var value = 1 }
                class Child: Base {}
                """,
            "Use.swift": """
                extension Child { func projection() -> Int { self.$value + $value } }
                """
        ])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Box", "projectedValue")))
        #expect(used.contains(try fixture.identity("Base", "value")))
    }

    @Test
    func chainedAnnotatedMemberReceiverResolvesWithoutPreservingOtherWrapper() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Box var value = 1 }
            struct Holder {
                var model: Model
                func read() -> Int { self.model.$value }
            }
            """])
        #expect(fixture.resolve().contains(try fixture.identity("Box", "projectedValue")))
    }

    @Test
    func rootedAndChainedKeyPathsKeepOnlyReferencedProjection() throws {
        let fixture = PropertyWrapperResolverFixture.parse(["Example.swift": #"""
            @propertyWrapper struct Used {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            @propertyWrapper struct Unused {
                var wrappedValue: Int
                var projectedValue: Int { wrappedValue }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct First { @Used var value = 1 }
            struct Second { @Unused var value = 2 }
            struct Holder { var model: First }
            let first = \First.$value
            let chained = \Holder.model.$value
            let second = \Second.value
            """#])
        let used = fixture.resolve()
        #expect(used.contains(try fixture.identity("Used", "projectedValue")))
        #expect(!used.contains(try fixture.identity("Unused", "projectedValue")))
    }
}
