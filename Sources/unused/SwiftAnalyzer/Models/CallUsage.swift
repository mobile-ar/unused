struct CallUsage: Hashable, Sendable {
    let kind: MemberKind
    var receiverType: String? = nil
    var argumentLabels: [String] = []
    var hasTrailingClosure = false
    var trailingClosureIndex: Int? = nil
    var isDynamicReceiver = false
    var enclosingTypePath: [String] = []
}
