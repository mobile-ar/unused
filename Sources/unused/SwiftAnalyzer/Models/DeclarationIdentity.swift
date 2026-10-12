struct DeclarationIdentity: Codable, Hashable, Sendable {
    let file: String
    let offset: Int
    let signature: MemberSignature
    var moduleName: String? = nil
    var enclosingTypePath: [String] = []
    var lexicalScope: [Int] = []
    var isTypeMember = true

    var ownerName: String? {
        enclosingTypePath.isEmpty ? nil : enclosingTypePath.joined(separator: ".")
    }
}
