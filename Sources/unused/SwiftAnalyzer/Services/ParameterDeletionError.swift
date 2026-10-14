import Foundation

struct ParameterDeletionError: LocalizedError {
    let parameterName: String

    var errorDescription: String? {
        "Cannot automatically delete unused local parameter binding '\(parameterName)'. "
            + "Signature removal is not proven safe. Review the binding manually and keep the callable signature unchanged. "
            + "No changes were made to this file."
    }
}
