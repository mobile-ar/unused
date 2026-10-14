enum ImportUsageUncertainty: Hashable, Sendable {
    case recoveredSyntax
    case macroExpansion(String)
    case attributeExpansion(String)
    case implicitMember
    case restrictedImport
    case submoduleImport
}
