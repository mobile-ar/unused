import Synchronization
import Testing
@testable import unused

struct SwiftInterfaceClientTests {
    @Test
    func injectedInterfacesAreIndexedOnceAcrossAllQueries() async throws {
        let loads = Mutex<[String: Int]>([:])
        let source = """
        public protocol Parent { func parent() }
        public protocol Child: Memory::Parent { func child() }
        public protocol Empty {}
        public typealias Partial = Child & Missing
        @propertyWrapper
        public struct Wrapper { public var wrappedValue: Int }
        """
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { moduleName in
            loads.withLock { $0[moduleName, default: 0] += 1 }
            return moduleName == "Memory" ? source : nil
        })
        let definition = try #require(await client.getProtocolDefinition(protocolName: "Child", inModule: "Memory"))
        #expect(definition.isComplete)
        #expect(definition.inheritedTypes == ["Memory.Parent"])
        #expect(await client.getProtocolRequirements(protocolName: "Child", inModule: "Memory") == ["child"])
        #expect(await client.getProtocolParents(protocolName: "Child", inModule: "Memory") == ["Parent"])
        #expect(await client.getProtocolRequirements(protocolName: "Empty", inModule: "Memory") == [])
        #expect(await client.getProtocolDefinition(protocolName: "Missing", inModule: "Memory") == nil)
        #expect(await client.getProtocolDefinition(protocolName: "Other.Child", inModule: "Memory") == nil)
        let partial = try #require(await client.getProtocolDefinition(protocolName: "Partial", inModule: "Memory"))
        #expect(!partial.isComplete)
        #expect(Set(partial.requirements.map(\.name)) == ["child"])
        #expect(await client.getTypeKind(typeName: "Wrapper", inModule: "Memory") == "struct")
        #expect(await client.getTypeKind(typeName: "Memory.Child", inModule: "Memory") == "protocol")
        #expect(await client.getTypeKind(typeName: "Other.Wrapper", inModule: "Memory") == nil)
        #expect(await client.getPropertyWrappers(inModule: "Memory") == ["Wrapper"])
        let inventory = await client.getSymbolInventory(inModule: "Memory")
        #expect(inventory.isComplete)
        #expect(inventory.symbols == [
            "Parent", "parent", "Child", "child", "Empty", "Partial", "Wrapper", "wrappedValue"
        ])
        #expect(loads.withLock { $0 } == ["Memory": 1])
    }

    @Test
    func knownStructsAndSDKClassesHaveMetadataWithoutProtocolDefinitions() async {
        let sources = [
            "Swift": "public struct String {}",
            "SDK": "public class SDKClass {}; public struct String {}; public protocol Empty {}"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        #expect(await client.getTypeKind(typeName: "String", inModule: "Swift") == "struct")
        #expect(await client.getTypeKind(typeName: "Swift::String", inModule: "Swift") == "struct")
        #expect(await client.getProtocolDefinition(protocolName: "String", inModule: "Swift") == nil)
        #expect(await client.getTypeKind(typeName: "SDKClass", inModule: "SDK") == "class")
        #expect(await client.getTypeKind(typeName: "SDK.SDKClass", inModule: "SDK") == "class")
        #expect(await client.getProtocolDefinition(protocolName: "SDKClass", inModule: "SDK") == nil)
        #expect(await client.getTypeKind(typeName: "Empty", inModule: "SDK") == "protocol")
        #expect(await client.getProtocolDefinition(protocolName: "Empty", inModule: "SDK")?.isComplete == true)
        #expect(await client.getTypeKind(typeName: "Swift.String", inModule: "SDK") == nil)
        #expect(await client.getTypeKind(typeName: "SDK.String", inModule: "Swift") == nil)
        #expect(await client.getTypeKind(typeName: "Other::SDKClass", inModule: "SDK") == nil)
        #expect(await client.getTypeKind(typeName: "NSObject", inModule: "SDK") == nil)
    }

    @Test
    func nestedTypeKindsRemainScopedAndModuleQualified() async {
        let source = """
        public struct Outer {
            public class Nested {}
            public enum Choice {}
            public actor Worker {}
            public protocol Requirement {}
            public struct `repeat` {}
        }
        public enum Other { public struct Nested {} }
        extension SDK::Outer { public struct FromExtension {} }
        """
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { $0 == "SDK" ? source : nil })
        #expect(await client.getTypeKind(typeName: "Outer.Nested", inModule: "SDK") == "class")
        #expect(await client.getTypeKind(typeName: "SDK::Outer.Nested", inModule: "SDK") == "class")
        #expect(await client.getTypeKind(typeName: "SDK.Outer.Choice", inModule: "SDK") == "enum")
        #expect(await client.getTypeKind(typeName: "Outer.Worker", inModule: "SDK") == "actor")
        #expect(await client.getTypeKind(typeName: "Outer.Requirement", inModule: "SDK") == "protocol")
        #expect(await client.getTypeKind(typeName: "SDK.Outer.`repeat`", inModule: "SDK") == "struct")
        #expect(await client.getTypeKind(typeName: "Other.Nested", inModule: "SDK") == "struct")
        #expect(await client.getTypeKind(typeName: "Outer.FromExtension", inModule: "SDK") == "struct")
        #expect(await client.getTypeKind(typeName: "SDK.Outer.FromExtension", inModule: "SDK") == "struct")
        #expect(await client.getTypeKind(typeName: "Foreign.Outer.Nested", inModule: "SDK") == nil)
        #expect(await client.getTypeKind(typeName: "Nested", inModule: "SDK") == nil)
    }

    @Test
    func injectedProvidersKeepSameModuleNamesIsolatedBetweenClients() async {
        let firstLoads = Mutex<Int>(0)
        let secondLoads = Mutex<Int>(0)
        let first = SwiftInterfaceClient(moduleInterfaceProvider: { _ in
            firstLoads.withLock { $0 += 1 }
            return "public protocol P { func first() }; public struct Type {}"
        })
        let second = SwiftInterfaceClient(moduleInterfaceProvider: { _ in
            secondLoads.withLock { $0 += 1 }
            return "public protocol P { func second() }; public class Type {}"
        })
        let unavailable = SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil })
        #expect(await first.getProtocolRequirements(protocolName: "P", inModule: "Swift") == ["first"])
        #expect(await second.getProtocolRequirements(protocolName: "P", inModule: "Swift") == ["second"])
        #expect(await unavailable.getProtocolDefinition(protocolName: "P", inModule: "Swift") == nil)
        #expect(await first.getTypeKind(typeName: "Type", inModule: "Swift") == "struct")
        #expect(await second.getTypeKind(typeName: "Type", inModule: "Swift") == "class")
        #expect(firstLoads.withLock { $0 } == 1)
        #expect(secondLoads.withLock { $0 } == 1)
    }

    @Test
    func unavailableModulesAreCachedAcrossQueries() async {
        let loads = Mutex<Int>(0)
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in
            loads.withLock { $0 += 1 }
            return nil
        })
        #expect(await client.getProtocolDefinition(protocolName: "P", inModule: "Missing") == nil)
        #expect(await client.getProtocolRequirements(protocolName: "P", inModule: "Missing") == nil)
        #expect(await client.getProtocolParents(protocolName: "P", inModule: "Missing") == nil)
        let inventory = await client.getSymbolInventory(inModule: "Missing")
        #expect(inventory.symbols.isEmpty)
        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties == [.unavailableModule("Missing")])
        #expect(await client.getPropertyWrappers(inModule: "Missing") == nil)
        #expect(await client.getTypeKind(typeName: "String", inModule: "Missing") == nil)
        #expect(loads.withLock { $0 } == 1)
    }

    @Test
    func concurrentQueriesShareOneModuleSnapshot() async {
        let loads = Mutex<Int>(0)
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { _ in
            loads.withLock { $0 += 1 }
            return "public protocol P { func requirement(_ value: Int) }"
        })
        let definitions = await withTaskGroup(of: ProtocolDefinition?.self, returning: [ProtocolDefinition?].self) { group in
            for _ in 0..<20 {
                group.addTask { await client.getProtocolDefinition(protocolName: "P", inModule: "Memory") }
            }
            var results: [ProtocolDefinition?] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(definitions.count == 20)
        #expect(definitions.allSatisfy { $0?.isComplete == true && $0?.requirements.count == 1 })
        #expect(loads.withLock { $0 } == 1)
    }

    @Test
    func combinesWrappersFromIndependentModulesAndKeepsEmptyModulesAvailable() async {
        let sources = [
            "First": "@propertyWrapper public struct One {}",
            "Second": "@propertyWrapper public struct Two {}",
            "Empty": "// No declarations"
        ]
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { sources[$0] })
        #expect(await client.getAllPropertyWrappers(fromModules: ["First", "Second", "Missing", "Empty"]) == ["One", "Two"])
        #expect(await client.getPropertyWrappers(inModule: "Empty") == [])
        let inventory = await client.getSymbolInventory(inModule: "Empty")
        #expect(inventory.symbols.isEmpty)
        #expect(!inventory.isComplete)
        #expect(inventory.uncertainties == [.emptyInterface])
        #expect(await client.getProtocolDefinition(protocolName: "P", inModule: "Empty") == nil)
        #expect(await client.getProtocolDefinition(protocolName: "One", inModule: "First") == nil)
    }
}
