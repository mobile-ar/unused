import Synchronization
import Testing
@testable import unused

struct SDKInterfaceCacheTests {
    @Test
    func concurrentClientsShareOneLoadedModuleIndex() async {
        let loads = Mutex<[String: Int]>([:])
        let source = """
        public protocol P { func requirement() }
        @propertyWrapper public struct Wrapper { public var wrappedValue: Int }
        """
        let cache = SDKInterfaceCache(moduleInterfaceProvider: { moduleName in
            loads.withLock { $0[moduleName, default: 0] += 1 }
            return source
        })
        let clients = (0..<20).map { _ in SwiftInterfaceClient(interfaceCache: cache) }
        let requirements = await withTaskGroup(of: Set<String>?.self, returning: [Set<String>?].self) { group in
            for client in clients {
                group.addTask { await client.getProtocolRequirements(protocolName: "P", inModule: "Memory") }
            }
            var results: [Set<String>?] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(requirements.count == 20)
        #expect(requirements.allSatisfy { $0 == ["requirement"] })
        #expect(await clients[0].getProtocolParents(protocolName: "P", inModule: "Memory") == [])
        #expect(await clients[1].getTypeKind(typeName: "Memory.Wrapper", inModule: "Memory") == "struct")
        #expect(await clients[2].getPropertyWrappers(inModule: "Memory") == ["Wrapper"])
        #expect(await clients[3].getExportedSymbols(inModule: "Memory") == ["P", "requirement", "Wrapper", "wrappedValue"])
        #expect(loads.withLock { $0 } == ["Memory": 1])
    }

    @Test
    func unavailableModulesAreSharedAcrossClientsAndQueries() async {
        let loads = Mutex<Int>(0)
        let cache = SDKInterfaceCache(moduleInterfaceProvider: { _ in
            loads.withLock { $0 += 1 }
            return nil
        })
        let first = SwiftInterfaceClient(interfaceCache: cache)
        let second = SwiftInterfaceClient(interfaceCache: cache)
        #expect(await first.getProtocolDefinition(protocolName: "P", inModule: "Missing") == nil)
        #expect(await second.getProtocolRequirements(protocolName: "P", inModule: "Missing") == nil)
        #expect(await second.getProtocolParents(protocolName: "P", inModule: "Missing") == nil)
        #expect(await first.getPropertyWrappers(inModule: "Missing") == nil)
        #expect(await second.getExportedSymbols(inModule: "Missing") == nil)
        #expect(await first.getTypeKind(typeName: "String", inModule: "Missing") == nil)
        #expect(await cache.index(forModule: "Missing") == nil)
        #expect(loads.withLock { $0 } == 1)
    }

    @Test
    func modulesRemainIndependentAndEmptyInterfacesRemainAvailable() async throws {
        let loads = Mutex<[String: Int]>([:])
        let sources = [
            "First": "public struct Type {}",
            "Second": "public class Type {}",
            "Empty": "// No declarations"
        ]
        let cache = SDKInterfaceCache(moduleInterfaceProvider: { moduleName in
            loads.withLock { $0[moduleName, default: 0] += 1 }
            return sources[moduleName]
        })
        let first = SwiftInterfaceClient(interfaceCache: cache)
        let second = SwiftInterfaceClient(interfaceCache: cache)
        #expect(await first.getTypeKind(typeName: "Type", inModule: "First") == "struct")
        #expect(await second.getTypeKind(typeName: "Type", inModule: "Second") == "class")
        #expect(await first.getTypeKind(typeName: "Second.Type", inModule: "First") == nil)
        #expect(await second.getExportedSymbols(inModule: "Empty") == [])
        let empty = try #require(await cache.index(forModule: "Empty"))
        #expect(empty.typeKinds.isEmpty)
        #expect(await first.getExportedSymbols(inModule: "Empty") == [])
        #expect(loads.withLock { $0 } == ["First": 1, "Second": 1, "Empty": 1])
    }

    @Test
    func wrapperOnlyQueriesAreLazyThenPromoteWithoutReloadingOrLosingMetadata() async throws {
        let loads = Mutex<Int>(0)
        let fullParses = Mutex<Int>(0)
        let source = """
        public protocol P { func requirement() }
        @available(macOS 15, *)
        @propertyWrapper
        public struct Wrapper { public var wrappedValue: Int }
        public class SDKClass {}
        """
        let cache = SDKInterfaceCache(
            moduleInterfaceProvider: { _ in
                loads.withLock { $0 += 1 }
                return source
            },
            indexParser: { source, moduleName in
                fullParses.withLock { $0 += 1 }
                return SDKInterfaceIndex(moduleInterface: source, moduleName: moduleName)
            }
        )
        let first = SwiftInterfaceClient(interfaceCache: cache)
        let second = SwiftInterfaceClient(interfaceCache: cache)
        #expect(await first.getPropertyWrappers(inModule: "Memory") == ["Wrapper"])
        #expect(await second.getAllPropertyWrappers(fromModules: ["Memory"]) == ["Wrapper"])
        #expect(loads.withLock { $0 } == 1)
        #expect(fullParses.withLock { $0 } == 0)
        #expect(await second.getProtocolRequirements(protocolName: "P", inModule: "Memory") == ["requirement"])
        #expect(await first.getTypeKind(typeName: "SDKClass", inModule: "Memory") == "class")
        #expect(await first.getPropertyWrappers(inModule: "Memory") == ["Wrapper"])
        let index = try #require(await cache.index(forModule: "Memory"))
        #expect(index.typeKinds == ["P": "protocol", "Wrapper": "struct", "SDKClass": "class"])
        #expect(index.exportedSymbols == ["P", "requirement", "Wrapper", "wrappedValue", "SDKClass"])
        #expect(loads.withLock { $0 } == 1)
        #expect(fullParses.withLock { $0 } == 1)
    }

    @Test
    func fullIndexesRemainAuthoritativeAfterWrapperQueries() async throws {
        let fullParses = Mutex<Int>(0)
        let cache = SDKInterfaceCache(
            moduleInterfaceProvider: { _ in "@propertyWrapper public struct Wrapper {}; public protocol P { func required() }" },
            indexParser: { source, moduleName in
                fullParses.withLock { $0 += 1 }
                return SDKInterfaceIndex(moduleInterface: source, moduleName: moduleName)
            }
        )
        let original = try #require(await cache.index(forModule: "Memory"))
        #expect(await cache.wrappers(forModule: "Memory") == original.propertyWrappers)
        let afterWrappers = try #require(await cache.index(forModule: "Memory"))
        #expect(afterWrappers.typeKinds == original.typeKinds)
        #expect(afterWrappers.exportedSymbols == original.exportedSymbols)
        #expect(afterWrappers.protocolDefinition(named: "P")?.requirements == original.protocolDefinition(named: "P")?.requirements)
        #expect(fullParses.withLock { $0 } == 1)
    }

    @Test
    func wrapperFirstUnavailableAndEmptyModulesAreCachedWithoutFullParsing() async {
        let loads = Mutex<[String: Int]>([:])
        let fullParses = Mutex<Int>(0)
        let cache = SDKInterfaceCache(
            moduleInterfaceProvider: { name in
                loads.withLock { $0[name, default: 0] += 1 }
                return name == "Empty" ? "// No wrappers" : nil
            },
            indexParser: { source, moduleName in
                fullParses.withLock { $0 += 1 }
                return SDKInterfaceIndex(moduleInterface: source, moduleName: moduleName)
            }
        )
        #expect(await cache.wrappers(forModule: "Empty") == [])
        #expect(await cache.wrappers(forModule: "Empty") == [])
        #expect(await cache.wrappers(forModule: "Missing") == nil)
        #expect(await cache.index(forModule: "Missing") == nil)
        #expect(await cache.wrappers(forModule: "Missing") == nil)
        #expect(loads.withLock { $0 } == ["Empty": 1, "Missing": 1])
        #expect(fullParses.withLock { $0 } == 0)
    }

    @Test
    func returnedSnapshotsCannotMutateCachedMetadata() async throws {
        let cache = SDKInterfaceCache(moduleInterfaceProvider: { _ in "public struct Original {}" })
        var snapshot = try #require(await cache.index(forModule: "Memory"))
        snapshot.typeKinds["Original"] = "class"
        snapshot.exportedSymbols.removeAll()
        let cached = try #require(await cache.index(forModule: "Memory"))
        #expect(cached.typeKinds == ["Original": "struct"])
        #expect(cached.exportedSymbols == ["Original"])
    }
}
