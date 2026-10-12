enum MemberKind: String, Codable, Sendable {
    case function
    case initializer
    case `subscript`
    case property
    case associatedType
    case typealiasDeclaration
    case type
    case enumCase
    case parameter
}
