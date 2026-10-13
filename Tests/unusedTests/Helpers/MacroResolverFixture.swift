import Foundation
import SwiftParser
import Testing
@testable import unused

struct MacroResolverFixture {
    let declarations: [Declaration]
    let parsedFiles: [ParsedFile]
    let graph: WitnessTypeGraph

    static func parse(_ sources: [String: String], moduleName: String? = nil) -> Self {
        var files: [ParsedFile] = []
        var declarations: [Declaration] = []
        var kinds: [String: String] = [:]
        var inheritance: [String: Set<String>] = [:]
        var aliases: [String: Set<String>] = [:]
        var definitions: [String: ProtocolDefinition] = [:]
        for (name, source) in sources.sorted(by: { $0.key < $1.key }) {
            let url = URL(fileURLWithPath: "/MacroTests/" + name)
            let tree = Parser.parse(source: source)
            files.append(ParsedFile(url: url, source: source, sourceFile: tree))
            let visitor = DeclarationVisitor(filePath: url.path, protocolRequirements: [:], sourceFile: tree,
                                             moduleName: moduleName)
            visitor.walk(tree)
            declarations.append(contentsOf: visitor.declarations)
            let protocols = ProtocolVisitor(viewMode: .sourceAccurate)
            protocols.walk(tree)
            kinds.merge(protocols.typeKinds) { first, _ in first }
            definitions.merge(protocols.protocolDefinitions) { first, _ in first }
            inheritance.merge(protocols.typeInheritance) { $0.union($1) }
            aliases.merge(protocols.typeAliases) { $0.union($1) }
        }
        if let moduleName {
            for (name, kind) in Array(kinds) { kinds[moduleName + "." + name] = kind }
            for (name, targets) in Array(aliases) { aliases[moduleName + "." + name] = targets }
        }
        let knownNames = Set(kinds.keys).union(aliases.keys).union(definitions.keys).union(inheritance.keys)
        return Self(declarations: declarations, parsedFiles: files,
                    graph: WitnessTypeGraph(definitions: definitions, inheritance: inheritance, kinds: kinds,
                                            aliases: aliases, unresolved: [], knownNames: knownNames))
    }

    func resolve(propertyWrappers: Set<String> = []) -> MacroDependencyResolution {
        MacroDependencyResolver(declarations: declarations, parsedFiles: parsedFiles, graph: graph,
                                propertyWrappers: propertyWrappers).resolve()
    }

    func identity(
        _ owner: String?, _ name: String, labels: [String]? = nil, file: String? = nil,
        isTypeMember: Bool? = nil
    ) throws -> DeclarationIdentity {
        let matches = declarations.compactMap(\.identity).filter {
            $0.ownerName == owner && $0.signature.name == name
                && (labels == nil || $0.signature.parameterLabels == labels)
                && (file == nil || $0.file.hasSuffix("/" + (file ?? "")))
                && (isTypeMember == nil || $0.isTypeMember == isTypeMember)
        }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }
}
