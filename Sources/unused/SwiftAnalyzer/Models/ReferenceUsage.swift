struct ReferenceUsage: Hashable, Sendable {
    let name: String
    let kind: ReferenceKind
    let file: String
    let line: Int
    let column: Int
    var receiverType: String? = nil
    var isMember: Bool = false
    var argumentLabels: [String]? = nil
    var lexicalScope: [Int] = []
}
