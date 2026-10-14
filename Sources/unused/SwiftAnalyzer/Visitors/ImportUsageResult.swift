struct ImportUsageResult: Sendable {
    let imports: [ImportInfo]
    let usedIdentifiers: Set<String>
    let typeInheritances: [String: Set<String>]
    var qualifiedReferences: Set<String> = []
    var uncertainties: Set<ImportUsageUncertainty> = []

    /// A local proof only: callers must also rule out cross-file and transitive dependencies.
    /// Name matching deliberately retains homonymous exports rather than guessing symbol ownership.
    func canProveUnused(_ importInfo: ImportInfo, inventory: SDKInterfaceSymbolInventory) -> Bool {
        inventory.isComplete && uncertainties.isEmpty && importInfo.uncertainties.isEmpty
            && !importInfo.isReexported && !usedIdentifiers.contains(importInfo.moduleName)
            && inventory.symbols.isDisjoint(with: usedIdentifiers)
            && inventory.symbols.isDisjoint(with: qualifiedReferences)
    }
}
