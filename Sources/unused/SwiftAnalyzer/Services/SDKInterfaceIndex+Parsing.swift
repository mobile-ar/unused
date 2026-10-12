import SwiftParser

extension SDKInterfaceIndex {
    init(moduleInterface: String, moduleName: String? = nil) {
        // SDK interfaces use C++-style module separators that SwiftParser does not currently accept.
        let syntax = Parser.parse(source: SDKInterfaceSourceNormalizer.normalized(moduleInterface))
        let visitor = SDKInterfaceIndexVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        self = visitor.index
        self.moduleName = moduleName ?? Self.declaredModuleName(in: moduleInterface)
    }

    private static func declaredModuleName(in source: String) -> String? {
        for line in source.split(separator: "\n").prefix(20) where line.hasPrefix("// swift-module-flags:") {
            let flags = line.split(whereSeparator: { $0.isWhitespace })
            if let index = flags.firstIndex(of: "-module-name"), flags.index(after: index) < flags.endIndex {
                return String(flags[flags.index(after: index)])
            }
        }
        return nil
    }
}
