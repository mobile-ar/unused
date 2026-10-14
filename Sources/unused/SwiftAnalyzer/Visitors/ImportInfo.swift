struct ImportInfo: Sendable {
    let moduleName: String
    let line: Int
    let filePath: String
    var isReexported = false
    var uncertainties: Set<ImportUsageUncertainty> = []
}
