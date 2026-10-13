import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import unused

struct PropertyWrapperResolverFixture {
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
            let url = URL(fileURLWithPath: "/PropertyWrapperTests/" + name)
            let tree = Parser.parse(source: source)
            files.append(ParsedFile(url: url, source: source, sourceFile: tree))
            let visitor = DeclarationVisitor(filePath: url.path, protocolRequirements: [:], sourceFile: tree,
                                             moduleName: moduleName)
            visitor.walk(tree)
            declarations.append(contentsOf: visitor.declarations)
            let protocols = ProtocolVisitor()
            protocols.walk(tree)
            kinds.merge(protocols.typeKinds) { first, _ in first }
            definitions.merge(protocols.protocolDefinitions) { first, _ in first }
            for (name, parents) in protocols.typeInheritance { inheritance[name, default: []].formUnion(parents) }
            for (name, targets) in protocols.typeAliases { aliases[name, default: []].formUnion(targets) }
        }
        let knownNames = Set(kinds.keys).union(aliases.keys).union(definitions.keys).union(inheritance.keys)
        return Self(declarations: declarations, parsedFiles: files,
                    graph: WitnessTypeGraph(definitions: definitions, inheritance: inheritance, kinds: kinds,
                                            aliases: aliases, unresolved: [], knownNames: knownNames))
    }

    func resolve() -> Set<DeclarationIdentity> {
        PropertyWrapperDependencyResolver(declarations: declarations, parsedFiles: parsedFiles, graph: graph).resolve()
    }

    func identity(
        _ owner: String?, _ name: String, labels: [String]? = nil, types: [String]? = nil,
        file: String? = nil, kind: MemberKind? = nil
    ) throws -> DeclarationIdentity {
        let matches = declarations.compactMap(\.identity).filter {
            $0.ownerName == owner && $0.signature.name == name
                && (labels == nil || $0.signature.parameterLabels == labels)
                && (types == nil || $0.signature.parameterTypes == types)
                && (file == nil || $0.file.hasSuffix("/" + (file ?? "")))
                && (kind == nil || $0.signature.kind == kind)
        }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }

    func hooks(_ owner: String, in used: Set<DeclarationIdentity>) -> Set<DeclarationIdentity> {
        used.filter { $0.ownerName == owner }
    }
}
