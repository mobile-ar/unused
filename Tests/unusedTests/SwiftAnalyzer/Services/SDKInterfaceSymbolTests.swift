import Testing
@testable import unused

struct SDKInterfaceSymbolTests {
    private let parser = SwiftInterfaceParser(sdkPath: nil)

    @Test
    func propertyWrapperAttributesCanSpanLinesAndHaveQualifiedNames() {
        let source = """
        @available(macOS 15, *)
        @frozen
        @propertyWrapper
        public struct Wrapper<Value> { public var wrappedValue: Value }
        @Swift::propertyWrapper
        public class Qualified { public var wrappedValue: Int }
        #if SOME_FEATURE
        @propertyWrapper
        public enum Conditional { case value }
        #endif
        public struct Ordinary {}
        """
        #expect(parser.parsePropertyWrappers(from: source) == ["Wrapper", "Qualified", "Conditional"])
    }

    @Test
    func parseSymbolInventoryIgnoresDeclarationTextInCommentsStringsAndExecutableBodies() {
        let source = #"""
        /*
        public protocol Fake { func fake() }
        @propertyWrapper public struct FakeWrapper {}
        */
        // public class Commented {}
        public let text = "public struct StringType {}; @propertyWrapper struct StringWrapper {}"
        public func exported<T>(_ value: T) {
            struct Local {}
            func localFunction() {}
            let localVariable = "var fakeProperty: Int"
            switch value { case _: break }
        }
        public struct Real {
            public var property: Int {
                struct GetterLocal {}
                return 1
            }
        }
        """#
        let inventory = parser.parseSymbolInventory(from: source)
        #expect(inventory.isComplete)
        #expect(inventory.symbols == ["text", "exported", "Real", "property"])
        #expect(parser.parsePropertyWrappers(from: source).isEmpty)
        #expect(parser.parseProtocolDefinition(protocolName: "Fake", from: source) == nil)
    }

    @Test
    func parseSymbolInventoryIncludesAllEnumCasesBindingsAndConditionalMembers() {
        let source = """
        public enum Choice { case first, second(Int), `default` }
        public let firstValue: Int, secondValue: String
        public struct Outer {
            public struct Nested {}
            #if FIRST
            public func firstMethod<T>(_ value: T)
            #else
            public var otherProperty: Int { get }
            #endif
        }
        public extension Outer { typealias Alias = Int }
        """
        let inventory = parser.parseSymbolInventory(from: source)
        #expect(inventory.isComplete)
        #expect(inventory.symbols == [
            "Choice", "first", "second", "default", "firstValue", "secondValue",
            "Outer", "Nested", "firstMethod", "otherProperty", "Alias"
        ])
    }
}
