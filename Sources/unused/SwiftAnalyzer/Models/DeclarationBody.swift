struct DeclarationBody: Sendable {
    let declaration: DeclarationReference
    let references: [ReferenceUsage]
    var lexicalScope: [Int] = []
    var parameterLabels: [String]? = nil
    var offset: Int = 0
    var defaultedParameterIndices: Set<Int> = []
    var variadicParameterIndex: Int? = nil
}
