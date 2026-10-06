struct ReferenceEdge: Hashable, Sendable {
    let source: DeclarationReference
    let target: DeclarationReference
    let usage: ReferenceUsage
    let isAmbiguous: Bool
}
