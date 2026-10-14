//
//  Created by Fernando Romiti on 03/02/2026.
//

import Testing
@testable import unused

struct SwiftInterfaceParserTests {

    @Test
    func testParsePropertyWrappersFindsSimplePropertyWrapper() {
        let moduleInterface = """
        @propertyWrapper public struct State<Value> {
            public var wrappedValue: Value
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("State"))
        #expect(wrappers.count == 1)
    }

    @Test
    func testParsePropertyWrappersFindsMultipleWrappers() {
        let moduleInterface = """
        @propertyWrapper public struct State<Value> {
            public var wrappedValue: Value
        }

        @propertyWrapper public struct Binding<Value> {
            public var wrappedValue: Value
        }

        @propertyWrapper public class Published<Value> {
            public var wrappedValue: Value
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("State"))
        #expect(wrappers.contains("Binding"))
        #expect(wrappers.contains("Published"))
        #expect(wrappers.count == 3)
    }

    @Test
    func testParsePropertyWrappersHandlesAvailableAttribute() {
        let moduleInterface = """
        @available(iOS 13.0, macOS 10.15, *)
        @propertyWrapper public struct StateObject<ObjectType> where ObjectType : ObservableObject {
            public var wrappedValue: ObjectType
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("StateObject"))
        #expect(wrappers.count == 1)
    }

    @Test
    func testParsePropertyWrappersIgnoresNonPropertyWrapperTypes() {
        let moduleInterface = """
        public struct RegularStruct {
            public var value: Int
        }

        @propertyWrapper public struct ActualWrapper<Value> {
            public var wrappedValue: Value
        }

        public class RegularClass {
            public var name: String
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("ActualWrapper"))
        #expect(!wrappers.contains("RegularStruct"))
        #expect(!wrappers.contains("RegularClass"))
        #expect(wrappers.count == 1)
    }

    @Test
    func testParsePropertyWrappersHandlesEnumPropertyWrapper() {
        let moduleInterface = """
        @propertyWrapper public enum OptionalWrapper<Value> {
            case none
            case some(Value)
            public var wrappedValue: Value? { get }
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("OptionalWrapper"))
        #expect(wrappers.count == 1)
    }

    @Test
    func testParsePropertyWrappersWithoutPublicModifier() {
        let moduleInterface = """
        @propertyWrapper struct InternalWrapper<Value> {
            var wrappedValue: Value
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("InternalWrapper"))
        #expect(wrappers.count == 1)
    }

    @Test
    func testParsePropertyWrappersReturnsEmptySetForNoWrappers() {
        let moduleInterface = """
        public struct SomeStruct {
            public var value: Int
        }

        public class SomeClass {
            public var name: String
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.isEmpty)
    }

    @Test
    func testParsePropertyWrappersHandlesComplexModuleInterface() {
        let moduleInterface = """
        import Swift

        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        @propertyWrapper @frozen public struct State<Value> : DynamicProperty {
            public var wrappedValue: Value { get nonmutating set }
            public var projectedValue: Binding<Value> { get }
        }

        @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
        @frozen @propertyWrapper public struct Binding<Value> {
            public var wrappedValue: Value { get nonmutating set }
        }

        public protocol View {
            associatedtype Body : View
            @ViewBuilder var body: Self.Body { get }
        }

        @available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *)
        @propertyWrapper public struct AppStorage<Value> : DynamicProperty {
            public var wrappedValue: Value { get nonmutating set }
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("State"))
        #expect(wrappers.contains("Binding"))
        #expect(wrappers.contains("AppStorage"))
        #expect(!wrappers.contains("View"))
        #expect(wrappers.count == 3)
    }

    @Test
    func testParsePropertyWrappersWithFrozenAttribute() {
        let moduleInterface = """
        @frozen @propertyWrapper public struct FrozenWrapper<Value> {
            public var wrappedValue: Value
        }

        @propertyWrapper @frozen public struct AnotherFrozenWrapper<Value> {
            public var wrappedValue: Value
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let wrappers = parser.parsePropertyWrappers(from: moduleInterface)

        #expect(wrappers.contains("FrozenWrapper"))
        #expect(wrappers.contains("AnotherFrozenWrapper"))
        #expect(wrappers.count == 2)
    }

    @Test
    func testGetPropertyWrappersFromSwiftUIModule() {
        let parser = SwiftInterfaceParser()!
        guard let wrappers = parser.getPropertyWrappers(inModule: "SwiftUI") else {
            // SwiftUI might not be available in test environment, skip test
            return
        }

        // SwiftUI module contains some property wrappers (others are in SwiftUICore)
        #expect(wrappers.contains("AppStorage"))
        #expect(wrappers.contains("SceneStorage"))
        #expect(wrappers.contains("FocusState"))
    }

    @Test
    func testGetPropertyWrappersFromSwiftUICoreModule() {
        let parser = SwiftInterfaceParser()!
        guard let wrappers = parser.getPropertyWrappers(inModule: "SwiftUICore") else {
            // SwiftUICore might not be available in test environment, skip test
            return
        }

        // SwiftUICore contains the core property wrappers like State, Binding, etc.
        #expect(wrappers.contains("State"))
        #expect(wrappers.contains("Binding"))
        #expect(wrappers.contains("StateObject"))
        #expect(wrappers.contains("ObservedObject"))
        #expect(wrappers.contains("EnvironmentObject"))
        #expect(wrappers.contains("Environment"))
    }

    @Test
    func testGetPropertyWrappersFromCombineModule() {
        let parser = SwiftInterfaceParser()!
        guard let wrappers = parser.getPropertyWrappers(inModule: "Combine") else {
            // Combine might not be available in test environment, skip test
            return
        }

        // Verify Published is detected from Combine
        #expect(wrappers.contains("Published"))
    }

    @Test
    func testGetPropertyWrappersFromObservationModule() {
        let parser = SwiftInterfaceParser()!
        // Observation module may or may not have property wrappers depending on macOS version
        // Just verify the method doesn't crash and returns a valid result
        _ = parser.getPropertyWrappers(inModule: "Observation")
        // If we get here without crashing, the test passes
    }

    @Test
    func testParseProtocolParentsWithSingleParent() {
        let moduleInterface = """
        public protocol ChildProtocol : ParentProtocol {
            func childMethod()
        }

        public protocol ParentProtocol {
            func parentMethod()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "ChildProtocol", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("ParentProtocol") == true)
        #expect(parents?.count == 1)
    }

    @Test
    func testParseProtocolParentsWithMultipleParents() {
        let moduleInterface = """
        public protocol Combined : ProtocolA, ProtocolB {
            func combinedMethod()
        }

        public protocol ProtocolA {
            func methodA()
        }

        public protocol ProtocolB {
            func methodB()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "Combined", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("ProtocolA") == true)
        #expect(parents?.contains("ProtocolB") == true)
        #expect(parents?.count == 2)
    }

    @Test
    func testParseProtocolParentsWithNoParent() {
        let moduleInterface = """
        public protocol StandaloneProtocol {
            func doSomething()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "StandaloneProtocol", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.isEmpty == true)
    }

    @Test
    func testParseProtocolParentsWithModulePrefix() {
        let moduleInterface = """
        public protocol AsyncParsableCommand : ArgumentParser.ParsableCommand {
            mutating func run() async throws
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "AsyncParsableCommand", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("ParsableCommand") == true)
        #expect(parents?.count == 1)
    }

    @Test
    func testParseProtocolParentsProtocolNotFound() {
        let moduleInterface = """
        public protocol SomeOtherProtocol {
            func doSomething()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "NonExistentProtocol", from: moduleInterface)

        #expect(parents == nil)
    }

    @Test
    func testParseProtocolParentsWithAvailableAttribute() {
        let moduleInterface = """
        @available(macOS 10.15, iOS 13, *)
        public protocol AsyncCommand : BaseCommand {
            func execute() async throws
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "AsyncCommand", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("BaseCommand") == true)
    }

    @Test
    func testParseProtocolParentsWithGenericConstraint() {
        let moduleInterface = """
        public protocol TypedProtocol<Element> : BaseProtocol {
            associatedtype Element
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "TypedProtocol", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("BaseProtocol") == true)
    }

    @Test
    func testGetProtocolParentsFromSwiftModule() {
        let parser = SwiftInterfaceParser()!
        // Hashable inherits from Equatable in the Swift standard library
        let parents = parser.getProtocolParents(protocolName: "Hashable", inModule: "Swift")

        #expect(parents != nil)
        #expect(parents?.contains("Equatable") == true)
    }

    @Test
    func testGetProtocolParentsFromNonExistentModule() {
        let parser = SwiftInterfaceParser()!
        let parents = parser.getProtocolParents(protocolName: "SomeProtocol", inModule: "NonExistentModule")

        #expect(parents == nil)
    }

    @Test
    func testParseProtocolParentsWithMultipleModulePrefixedParents() {
        let moduleInterface = """
        public protocol MyProtocol : Swift.Equatable, Swift.Hashable {
            func myMethod()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let parents = parser.parseProtocolParents(protocolName: "MyProtocol", from: moduleInterface)

        #expect(parents != nil)
        #expect(parents?.contains("Equatable") == true)
        #expect(parents?.contains("Hashable") == true)
        #expect(parents?.count == 2)
    }

    @Test
    func testParseSymbolInventoryFindsStructs() {
        let moduleInterface = """
        public struct URL {
            public var absoluteString: String { get }
        }

        public struct Data {
            public var count: Int { get }
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("URL"))
        #expect(symbols.contains("Data"))
    }

    @Test
    func testParseSymbolInventoryFindsClasses() {
        let moduleInterface = """
        public class NSObject {
            public func description() -> String
        }

        public class JSONDecoder {
            public func decode<T>(_ type: T.Type, from data: Data) throws -> T
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("NSObject"))
        #expect(symbols.contains("JSONDecoder"))
    }

    @Test
    func testParseSymbolInventoryFindsEnums() {
        let moduleInterface = """
        public enum ComparisonResult : Int {
            case orderedAscending
            case orderedSame
            case orderedDescending
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("ComparisonResult"))
        #expect(symbols.contains("orderedAscending"))
        #expect(symbols.contains("orderedSame"))
        #expect(symbols.contains("orderedDescending"))
    }

    @Test
    func testParseSymbolInventoryFindsProtocols() {
        let moduleInterface = """
        public protocol Codable : Decodable, Encodable {
        }

        public protocol Identifiable {
            associatedtype ID
            var id: ID { get }
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("Codable"))
        #expect(symbols.contains("Identifiable"))
    }

    @Test
    func testParseSymbolInventoryFindsActors() {
        let moduleInterface = """
        public actor MyActor {
            public func perform()
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("MyActor"))
    }

    @Test
    func testParseSymbolInventoryFindsFunctions() {
        let moduleInterface = """
        public func print(_ items: Any...)
        public func abs<T>(_ x: T) -> T where T : Comparable
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("print"))
        #expect(symbols.contains("abs"))
    }

    @Test
    func testParseSymbolInventoryFindsVariables() {
        let moduleInterface = """
        public let pi: Double
        public var stderr: UnsafeMutablePointer<FILE>
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("pi"))
        #expect(symbols.contains("stderr"))
    }

    @Test
    func testParseSymbolInventoryFindsTypealiases() {
        let moduleInterface = """
        public typealias StringLiteralType = String
        public typealias IntegerLiteralType = Int
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("StringLiteralType"))
        #expect(symbols.contains("IntegerLiteralType"))
    }

    @Test
    func testParseSymbolInventoryIgnoresCommentsAndEmptyLines() {
        let moduleInterface = """
        // This is a comment
        /* Block comment */

        /// Documentation comment
        public struct RealType {
        }
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(inventory.isComplete)
        #expect(symbols.contains("RealType"))
        #expect(!symbols.contains("This"))
        #expect(!symbols.contains("Block"))
    }

    @Test(arguments: ["", "   \n", "// Only comments here", "import ClangOnly"])
    func testParseSymbolInventoryDoesNotTreatStubsAsComplete(_ moduleInterface: String) {
        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)

        #expect(inventory.symbols.isEmpty)
        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties == [.emptyInterface])
    }

    @Test
    func testParseSymbolInventoryRetainsKnownSymbolsFromMalformedInterfaces() {
        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: "public struct Known {}\npublic struct Broken {")

        #expect(inventory.symbols.contains("Known"))
        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties.contains(.recoveredSyntax))
    }

    @Test
    func testParseSymbolInventoryPreservesUnresolvedReexports() {
        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: "@_exported import Dependency\npublic struct Known {}")

        #expect(inventory.symbols == ["Known"])
        #expect(inventory.reexportedModules == ["Dependency"])
        #expect(!inventory.isComplete)
    }

    @Test
    func testParseSymbolInventoryComplexInterface() {
        let moduleInterface = """
        import Swift

        @available(iOS 13.0, macOS 10.15, *)
        @propertyWrapper @frozen public struct State<Value> : DynamicProperty {
            public var wrappedValue: Value { get nonmutating set }
            public var projectedValue: Binding<Value> { get }
        }

        public protocol View {
            associatedtype Body : View
            @ViewBuilder var body: Self.Body { get }
        }

        public struct Text : View {
            public var body: some View { get }
        }

        public enum Alignment {
            case leading
            case center
            case trailing
        }

        public typealias Animation = SwiftUI.Animation

        public func withAnimation<Result>(_ animation: Animation?, _ body: () throws -> Result) rethrows -> Result
        """

        let parser = SwiftInterfaceParser(sdkPath: nil)
        let inventory = parser.parseSymbolInventory(from: moduleInterface)
        let symbols = inventory.symbols

        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties.contains(.attributeExpansion("ViewBuilder")))
        #expect(symbols.contains("State"))
        #expect(symbols.contains("View"))
        #expect(symbols.contains("Text"))
        #expect(symbols.contains("Alignment"))
        #expect(symbols.contains("leading"))
        #expect(symbols.contains("center"))
        #expect(symbols.contains("trailing"))
        #expect(symbols.contains("Animation"))
        #expect(symbols.contains("withAnimation"))
        #expect(symbols.contains("wrappedValue"))
        #expect(symbols.contains("projectedValue"))
        #expect(symbols.contains("body"))
    }

    @Test
    func testSymbolInventoryFromInjectedModuleInterface() async {
        let source = """
        public struct String {}
        public struct Int {}
        public struct Array<Element> {}
        public struct Dictionary<Key, Value> {}
        public enum Optional<Wrapped> {}
        public struct Bool {}
        public func print(_ items: Any...)
        """
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { $0 == "Memory" ? source : nil })
        let inventory = await client.getSymbolInventory(inModule: "Memory")

        #expect(inventory.isComplete)
        #expect(inventory.symbols == ["String", "Int", "Array", "Dictionary", "Optional", "Bool", "print"])
    }

    @Test
    func testSymbolInventoryFromUnavailableModule() async {
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil })
        let inventory = await client.getSymbolInventory(inModule: "Missing")

        #expect(inventory.symbols.isEmpty)
        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties == [.unavailableModule("Missing")])
    }

}
