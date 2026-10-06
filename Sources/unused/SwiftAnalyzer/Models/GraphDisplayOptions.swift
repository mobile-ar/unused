struct GraphDisplayOptions: Sendable {
    var inboundOnly = false
    var outboundOnly = false
    var depth = 1
    var limit = 20
    var width = 100
    var ascii = false
    var color = false
    var directory: String? = nil
}
