import SwiftParser

extension SDKInterfaceIndex {
    init(moduleInterface: String, moduleName: String? = nil) {
        // SDK interfaces use C++-style module separators that SwiftParser does not currently accept.
        let syntax = Parser.parse(source: SDKInterfaceSourceNormalizer.normalized(moduleInterface))
        let visitor = SDKInterfaceIndexVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        self = visitor.index
        self.moduleName = moduleName ?? Self.declaredModuleName(in: moduleInterface)
        symbolInventoryUncertainties.remove(.unverifiedInterface)
        if Self.moduleFlags(in: moduleInterface).contains("-import-underlying-module")
            || self.moduleName.map({ importedModules.contains($0) }) == true {
            // A Swift overlay does not inventory the underlying Clang module's declarations.
            symbolInventoryUncertainties.insert(.underlyingModule)
        }
        if syntax.hasError {
            symbolInventoryUncertainties.insert(.recoveredSyntax)
        }
        if exportedSymbols.isEmpty && reexportedModules.isEmpty {
            // An opened file without declarations can be a stub or a Clang import shim.
            symbolInventoryUncertainties.insert(.emptyInterface)
        }
    }

    private static func declaredModuleName(in source: String) -> String? {
        let flags = moduleFlags(in: source)
        guard let index = flags.firstIndex(of: "-module-name"), flags.index(after: index) < flags.endIndex else {
            return nil
        }
        return String(flags[flags.index(after: index)])
    }

    private static func moduleFlags(in source: String) -> [Substring] {
        source.split(separator: "\n").prefix(20)
            .filter { $0.hasPrefix("// swift-module-flags:") }
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }) }
    }
}
