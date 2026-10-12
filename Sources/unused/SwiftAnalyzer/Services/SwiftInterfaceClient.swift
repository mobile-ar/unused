//
//  Created by Fernando Romiti on 18/01/2026.
//

actor SwiftInterfaceClient: Sendable {
    private static let sdkParser = SwiftInterfaceParser()
    private let interfaceCache: SDKInterfaceCache

    init(moduleInterfaceProvider: (@Sendable (String) -> String?)? = nil) {
        if let moduleInterfaceProvider {
            self.interfaceCache = SDKInterfaceCache(moduleInterfaceProvider: moduleInterfaceProvider)
        } else {
            self.interfaceCache = .shared
        }
    }

    init(interfaceCache: SDKInterfaceCache) {
        self.interfaceCache = interfaceCache
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

    func getExportedSymbols(inModule moduleName: String) async -> Set<String>? {
        (await interfaceCache.index(forModule: moduleName))?.exportedSymbols
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
