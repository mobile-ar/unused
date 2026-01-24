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

}
