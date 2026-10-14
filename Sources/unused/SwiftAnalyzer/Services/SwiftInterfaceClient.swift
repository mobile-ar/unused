//
//  Created by Fernando Romiti on 18/01/2026.
//

actor SwiftInterfaceClient: Sendable {
    private static let sdkParser = SwiftInterfaceParser()
    private let interfaceCache: SDKInterfaceCache
    private let symbolInventoryClient: SDKInterfaceSymbolInventoryClient

    init(
        moduleInterfaceProvider: (@Sendable (String) -> String?)? = nil,
        symbolInventoryProvider: (@Sendable (String) -> SDKInterfaceSymbolInventory?)? = nil
    ) {
        let cache: SDKInterfaceCache
        if let moduleInterfaceProvider {
            cache = SDKInterfaceCache(moduleInterfaceProvider: moduleInterfaceProvider)
        } else {
            cache = .shared
        }
        self.interfaceCache = cache
        self.symbolInventoryClient = SDKInterfaceSymbolInventoryClient(
            interfaceCache: cache, inventoryProvider: symbolInventoryProvider
        )
    }

    init(
        interfaceCache: SDKInterfaceCache,
        symbolInventoryProvider: (@Sendable (String) -> SDKInterfaceSymbolInventory?)? = nil
    ) {
        self.interfaceCache = interfaceCache
        self.symbolInventoryClient = SDKInterfaceSymbolInventoryClient(
            interfaceCache: interfaceCache, inventoryProvider: symbolInventoryProvider
        )
    }

    static func loadSDKModuleInterface(_ moduleName: String) -> String? {
        sdkParser?.getModuleInterface(moduleName: moduleName)
    }

    func getProtocolDefinition(protocolName: String, inModule moduleName: String) async -> ProtocolDefinition? {
        (await interfaceCache.index(forModule: moduleName))?.protocolDefinition(named: protocolName)
    }

    func getProtocolRequirements(protocolName: String, inModule moduleName: String) async -> Set<String>? {
        (await getProtocolDefinition(protocolName: protocolName, inModule: moduleName)).map { definition in
            Set(definition.requirements.map(\.name))
        }
    }

    func getProtocolParents(protocolName: String, inModule moduleName: String) async -> Set<String>? {
        (await getProtocolDefinition(protocolName: protocolName, inModule: moduleName)).map { definition in
            Set(definition.inheritedTypes.map(SDKInterfaceTypeReferences.leafName))
        }
    }

    func getTypeKind(typeName: String, inModule moduleName: String) async -> String? {
        (await interfaceCache.index(forModule: moduleName))?.typeKind(named: typeName)
    }

    func getPropertyWrappers(inModule moduleName: String) async -> Set<String>? {
        await interfaceCache.wrappers(forModule: moduleName)
    }

    func getSymbolInventory(inModule moduleName: String) async -> SDKInterfaceSymbolInventory {
        await symbolInventoryClient.inventory(inModule: moduleName)
    }

    func getAllPropertyWrappers(fromModules moduleNames: Set<String>) async -> Set<String> {
        var propertyWrappers = Set<String>()
        for moduleName in moduleNames.sorted() {
            if let wrappers = await getPropertyWrappers(inModule: moduleName) {
                propertyWrappers.formUnion(wrappers)
            }
        }
        return propertyWrappers
    }
}
