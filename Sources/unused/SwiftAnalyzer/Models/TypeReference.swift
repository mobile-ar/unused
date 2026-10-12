struct TypeReference: Codable, Hashable, Sendable {
    let name: String
    var enclosingTypePath: [String] = []
    var lexicalScope: [Int] = []
    var file: String? = nil
}
