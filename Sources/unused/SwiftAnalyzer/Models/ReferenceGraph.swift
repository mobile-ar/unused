struct ReferenceGraphResult: Sendable {
    let target: ReportItem

    var root: DeclarationReference? = nil
    var edges: [ReferenceEdge] = []
    var unresolved: [ReferenceUsage] = []
    var warnings: [String] = []
    var scannedFileCount: Int = 0
    var includesTests: Bool = true
    var targetFound: Bool = true

    var inbound: [DeclarationReference] {
        guard let root else { return [] }
        return neighbors(edges.filter { $0.target == root }.map(\.source))
    }

    var outbound: [DeclarationReference] {
        guard let root else { return [] }
        return neighbors(edges.filter { $0.source == root }.map(\.target))
    }

    private func neighbors(_ declarations: [DeclarationReference]) -> [DeclarationReference] {
        Set(declarations).sorted {
            if $0.file != $1.file { return $0.file < $1.file }
            if $0.line != $1.line { return $0.line < $1.line }
            if $0.column != $1.column { return $0.column < $1.column }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.kind < $1.kind
        }
    }
}
