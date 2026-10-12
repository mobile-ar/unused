/// Serializes module loading and lazily promotes wrapper-only results to syntax-free full indexes.
/// Source text is retained until promotion to avoid reading a module twice; syntax trees are never cached.
actor SDKInterfaceCache {
    static let shared = SDKInterfaceCache()

    private let moduleInterfaceProvider: @Sendable (String) -> String?
    private let indexParser: @Sendable (String, String) -> SDKInterfaceIndex
    private var moduleIndexes: [String: SDKInterfaceIndex] = [:]
    private var moduleInterfaces: [String: String] = [:]
    private var moduleWrappers: [String: Set<String>] = [:]
    private var unavailableModules: Set<String> = []

    init(
        moduleInterfaceProvider: @escaping @Sendable (String) -> String? = SwiftInterfaceClient.loadSDKModuleInterface,
        indexParser: @escaping @Sendable (String, String) -> SDKInterfaceIndex = {
            SDKInterfaceIndex(moduleInterface: $0, moduleName: $1)
        }
    ) {
        self.moduleInterfaceProvider = moduleInterfaceProvider
        self.indexParser = indexParser
    }

    func index(forModule moduleName: String) -> SDKInterfaceIndex? {
        if let index = moduleIndexes[moduleName] { return index }
        guard let interface = moduleInterface(named: moduleName) else { return nil }
        // No suspension until publication: concurrent callers cannot load or parse the same module twice.
        let index = indexParser(interface, moduleName)
        moduleIndexes[moduleName] = index
        moduleInterfaces.removeValue(forKey: moduleName)
        moduleWrappers.removeValue(forKey: moduleName)
        return index
    }

    func wrappers(forModule moduleName: String) -> Set<String>? {
        if let index = moduleIndexes[moduleName] { return index.propertyWrappers }
        if let wrappers = moduleWrappers[moduleName] { return wrappers }
        guard let interface = moduleInterface(named: moduleName) else { return nil }
        let wrappers = SDKInterfaceWrapperParser.wrappers(in: interface)
        moduleWrappers[moduleName] = wrappers
        return wrappers
    }

    private func moduleInterface(named moduleName: String) -> String? {
        if let interface = moduleInterfaces[moduleName] { return interface }
        guard !unavailableModules.contains(moduleName) else { return nil }
        guard let interface = moduleInterfaceProvider(moduleName) else {
            unavailableModules.insert(moduleName)
            return nil
        }
        moduleInterfaces[moduleName] = interface
        return interface
    }
}
