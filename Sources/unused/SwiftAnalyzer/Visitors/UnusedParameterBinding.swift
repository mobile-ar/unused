/// An unused local binding, not evidence that the callable's argument can be removed.
///
/// Reporting or refactoring this finding must preserve the callable signature. Even a
/// private callable may be invoked with side-effecting arguments or used as a function value.
struct UnusedParameterBinding: Sendable {
    let name: String
    let file: String
    let line: Int
    let parentType: String
    let identity: DeclarationIdentity
}
