/// Resolves the complete re-export graph without retaining syntax or treating cycles as missing modules.
/// Injected inventories are authoritative and do not fall back to the installed SDK.
actor SDKInterfaceSymbolInventoryClient {
    private let interfaceCache: SDKInterfaceCache
    private let inventoryProvider: (@Sendable (String) -> SDKInterfaceSymbolInventory?)?
    private var moduleInventories: [String: SDKInterfaceSymbolInventory] = [:]
    private var resolvedInventories: [String: SDKInterfaceSymbolInventory] = [:]

    init(
        interfaceCache: SDKInterfaceCache,
        inventoryProvider: (@Sendable (String) -> SDKInterfaceSymbolInventory?)? = nil
    ) {
        self.interfaceCache = interfaceCache
        self.inventoryProvider = inventoryProvider
    }

    func inventory(inModule moduleName: String) async -> SDKInterfaceSymbolInventory {
        if let inventory = resolvedInventories[moduleName] { return inventory }
        var result = SDKInterfaceSymbolInventory()
        var pending = [moduleName]
        var visited: Set<String> = []
        while let module = pending.popLast() {
            guard visited.insert(module).inserted else { continue }
            let inventory = await directInventory(inModule: module)
            result.symbols.formUnion(inventory.symbols)
            result.uncertainties.formUnion(inventory.uncertainties)
            pending.append(contentsOf: inventory.reexportedModules.sorted())
        }
        resolvedInventories[moduleName] = result
        return result
    }

    private func directInventory(inModule moduleName: String) async -> SDKInterfaceSymbolInventory {
        if let inventory = moduleInventories[moduleName] { return inventory }
        let inventory: SDKInterfaceSymbolInventory
        if let inventoryProvider {
            inventory = inventoryProvider(moduleName) ?? SDKInterfaceSymbolInventory(
                uncertainties: [.unavailableModule(moduleName)]
            )
        } else if let index = await interfaceCache.index(forModule: moduleName) {
            inventory = index.symbolInventory
        } else {
            inventory = SDKInterfaceSymbolInventory(uncertainties: [.unavailableModule(moduleName)])
        }
        moduleInventories[moduleName] = inventory
        return inventory
    }
}
