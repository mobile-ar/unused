enum ReferenceKind: String, Hashable, Sendable {
    case call
    case read
    case write
    case type
    case reference
}
