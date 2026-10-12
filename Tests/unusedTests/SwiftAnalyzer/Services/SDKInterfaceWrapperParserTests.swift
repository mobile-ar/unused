import Testing
@testable import unused

struct SDKInterfaceWrapperParserTests {
    @Test
    func parsesMultilineAttributesNamesAndGenericDeclarationHeaders() {
        let source = ###"""
        @available(
            macOS 15,
            message: "text { @propertyWrapper struct Fake {} }"
        )
        @frozen
        @propertyWrapper
        @preconcurrency
        @Module::MainActor
        public struct
        Wrapper<Value>
        where Value: Module::Protocol {
            public var wrappedValue: Value
        }
        @Swift::propertyWrapper
        public class Qualified {}
        @propertyWrapper public enum EnumWrapper { case value }
        @propertyWrapper public struct `repeat` {}
        @propertyWrapper public struct Café {}
        """###
        let wrappers = SDKInterfaceWrapperParser.wrappers(in: source)
        #expect(wrappers == ["Wrapper", "Qualified", "EnumWrapper", "repeat", "Café"])
        #expect(wrappers == SDKInterfaceIndex(moduleInterface: source).propertyWrappers)
    }

    @Test
    func traversesNestedTypesExtensionsAndAllConditionalBranches() {
        let source = """
        public struct Outer {
            #if FIRST
            @propertyWrapper public struct First {}
            #else
            @propertyWrapper public class Second {}
            #endif
            public struct Nested { @propertyWrapper public struct Third {} }
        }
        public extension Outer { @propertyWrapper public struct FromExtension {} }
        #if ANOTHER_FEATURE
        @propertyWrapper public struct TopLevel {}
        #endif
        """
        let wrappers = SDKInterfaceWrapperParser.wrappers(in: source)
        #expect(wrappers == ["First", "Second", "Third", "FromExtension", "TopLevel"])
        #expect(wrappers == SDKInterfaceIndex(moduleInterface: source).propertyWrappers)
    }

    @Test
    func skipsCommentsStringsInterpolationsAndExecutableBodies() {
        let source = ####"""
        // @propertyWrapper struct LineComment {}
        /* outer /* @propertyWrapper struct BlockComment {} */ outer */
        public let ordinary = "@propertyWrapper struct Literal {}"
        public let raw = ##"@propertyWrapper struct RawLiteral {}"##
        public let interpolation = "value \({ @propertyWrapper struct Interpolated {}; return 1 }())"
        public let rawMultiline = ##"""
        @propertyWrapper struct RawMultiline {}
        """##
        public func perform(_ callback: () -> Void = { @propertyWrapper struct DefaultValue {} }) {
            let text = "} @propertyWrapper struct BodyString {}"
            @propertyWrapper struct Local {}
        }
        public class Container {
            public class func perform() { @propertyWrapper struct LocalClassFunction {} }
            public var computed: Int {
                @propertyWrapper struct GetterLocal {}
                return 1
            }
            public init() { @propertyWrapper struct InitializerLocal {} }
            public subscript(_ index: Int) -> Int { @propertyWrapper struct SubscriptLocal {}; return 0 }
            @propertyWrapper public struct Actual {}
        }
        """####
        #expect(SDKInterfaceWrapperParser.wrappers(in: source) == ["Actual"])
        #expect(SDKInterfaceWrapperParser.wrappers(in: source) == SDKInterfaceIndex(moduleInterface: source).propertyWrappers)
    }

    @Test
    func attributesOnOtherDeclarationsCannotLeakOntoTypes() {
        let source = """
        @propertyWrapper func notAType() {}
        public struct Plain {}
        @propertyWrapper var notATypeEither: Int { get }
        public class Other {}
        @propertyWrapperish public struct SimilarlyNamed {}
        """
        #expect(SDKInterfaceWrapperParser.wrappers(in: source).isEmpty)
        #expect(SDKInterfaceIndex(moduleInterface: source).propertyWrappers.isEmpty)
    }

    @Test
    func largeUnrelatedBodiesDoNotAffectWrapperSelection() {
        let body = Array(repeating: "public func unrelated(_ value: Int) -> Int { return value }", count: 2_000).joined(separator: "\n")
        let source = """
        public struct Unrelated {
        \(body)
        }
        @propertyWrapper
        public struct Small<Value> { public var wrappedValue: Value }
        """
        #expect(SDKInterfaceWrapperParser.wrappers(in: source) == ["Small"])
    }

    @Test
    func truncatedAndConditionalAttributeHeadersMatchFullParsing() {
        let sources = [
            "@propertyWrapper public struct Truncated<Value>",
            "#if FIRST\n@propertyWrapper\n#else\n@frozen\n#endif\npublic struct Conditional {}",
            "#if FIRST\n@frozen\n#else\n@propertyWrapper\n#endif\npublic struct Conditional {}",
            "@propertyWrapper\n#if FIRST\n@frozen\n#endif\npublic struct Conditional {}"
        ]
        for source in sources {
            #expect(SDKInterfaceWrapperParser.wrappers(in: source) == SDKInterfaceIndex(moduleInterface: source).propertyWrappers)
        }
        #expect(SDKInterfaceWrapperParser.wrappers(in: sources[0]) == ["Truncated"])
    }

    @Test
    func regexLiteralContentsCannotIntroduceWrapperDeclarations() {
        let source = ###"""
        public let bare = /@propertyWrapper struct BareFake \{\}/
        public let extended = #/@propertyWrapper struct RawFake \{\}/#
        @propertyWrapper public struct Actual {}
        """###
        #expect(SDKInterfaceWrapperParser.wrappers(in: source) == ["Actual"])
        #expect(SDKInterfaceWrapperParser.wrappers(in: source) == SDKInterfaceIndex(moduleInterface: source).propertyWrappers)
    }

    @Test
    func emptyInterfacesAndUnmarkedTypesHaveNoWrappers() {
        for source in ["", "// No declarations", "public struct Plain {}", "public let marker = \"propertyWrapper\""] {
            #expect(SDKInterfaceWrapperParser.wrappers(in: source).isEmpty)
        }
    }
}
