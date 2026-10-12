struct MemberSignature: Codable, Hashable, Sendable {
    let kind: MemberKind
    let name: String
    var isStatic = false
    var parameterLabels: [String] = []
    var parameterTypes: [String] = []
    var resultType: String? = nil
    var genericParameters: [String] = []
    var isAsync = false
    var isThrowing = false
}
