import SwiftSyntax

struct ParameterBindingInfo {
    let name: String
    let token: TokenSyntax
    let hasPotentialWrapperAttribute: Bool

    func isReferenced(in identifiers: Set<String>) -> Bool {
        if identifiers.contains(name) {
            return true
        }
        // Without a resolved attribute inventory, retain any potentially wrapped binding
        // referenced through its compiler-generated projection or backing storage.
        return hasPotentialWrapperAttribute
            && (identifiers.contains("$" + name) || identifiers.contains("_" + name))
    }
}
