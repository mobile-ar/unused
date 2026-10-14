/// Known exported names, including member, operator and macro names.
/// An empty set proves absence only when parsing and every re-export are complete.
struct SDKInterfaceSymbolInventory: Equatable, Sendable {
    var symbols: Set<String> = []
    var reexportedModules: Set<String> = []
    var uncertainties: Set<SDKInterfaceSymbolInventoryUncertainty> = []

    var isComplete: Bool {
        uncertainties.isEmpty && reexportedModules.isEmpty
    }
}

enum SDKInterfaceSymbolInventoryUncertainty: Hashable, Sendable {
    case unverifiedInterface
    case emptyInterface
    case recoveredSyntax
    case unavailableModule(String)
    case scopedReexport(String)
    case underlyingModule
    case implicitExports
    case macroExpansion
    case attributeExpansion(String)
    case unrepresentedDeclaration
}
