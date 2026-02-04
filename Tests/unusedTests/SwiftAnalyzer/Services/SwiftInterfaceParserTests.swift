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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

        let parser = SwiftInterfaceParser()!
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

}
