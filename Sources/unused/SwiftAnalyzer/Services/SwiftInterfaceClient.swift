//
//  Created by Fernando Romiti on 18/01/2026.
//

import Foundation

actor SwiftInterfaceClient: Sendable {

    private lazy var parser: SwiftInterfaceParser? = SwiftInterfaceParser()

    /// Get protocol requirements by querying the module interface
    /// - Parameters:
    ///   - protocolName: The name of the protocol
    ///   - moduleName: The module containing the protocol (e.g., "Swift", "Foundation")
    /// - Returns: A set of method/property names required by the protocol, or nil if unavailable
    func getProtocolRequirements(protocolName: String, inModule moduleName: String) -> Set<String>? {
        return parser?.getProtocolRequirements(protocolName: protocolName, inModule: moduleName)
    }

    /// Get parent protocols of a protocol by querying the module interface
    /// - Parameters:
    ///   - protocolName: The name of the protocol
    ///   - moduleName: The module containing the protocol (e.g., "Swift", "Foundation")
    /// - Returns: A set of parent protocol names, or nil if unavailable
    func getProtocolParents(protocolName: String, inModule moduleName: String) -> Set<String>? {
        return parser?.getProtocolParents(protocolName: protocolName, inModule: moduleName)
    }

    /// Get all property wrapper type names from a module
    /// - Parameter moduleName: The name of the module to query
    /// - Returns: A set of property wrapper type names, or nil if the module is unavailable
    func getPropertyWrappers(inModule moduleName: String) -> Set<String>? {
        return parser?.getPropertyWrappers(inModule: moduleName)
    }

    /// Get all exported symbol names from a module
    /// - Parameter moduleName: The name of the module to query
    /// - Returns: A set of exported symbol names, or nil if the module is unavailable
    func getExportedSymbols(inModule moduleName: String) -> Set<String>? {
        return parser?.getExportedSymbols(inModule: moduleName)
    }

    /// Get all property wrappers from multiple modules
    /// - Parameter moduleNames: The set of module names to query
    /// - Returns: A combined set of all property wrapper type names found
    func getAllPropertyWrappers(fromModules moduleNames: Set<String>) -> Set<String> {
        var allPropertyWrappers = Set<String>()

        for moduleName in moduleNames {
            if let wrappers = parser?.getPropertyWrappers(inModule: moduleName) {
                allPropertyWrappers.formUnion(wrappers)
            }
        }

        return allPropertyWrappers
    }

}
