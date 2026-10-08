struct ProgressUpdate: Equatable, Sendable {
    let prefix: String
    let current: Int
    let total: Int
    let estimatedRemaining: Duration?
    var elapsed: Duration? = nil
}
