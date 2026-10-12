import Foundation
import SwiftParser
import SwiftSyntax

struct ReferenceGraphService {
    var discoverFiles: @Sendable (URL, Bool) async -> SwiftFileDiscoveryResult = {
        await getSwiftFiles(in: $0, includeTests: $1)
    }
    var readSource: @Sendable (URL) throws -> String = {
        try String(contentsOf: $0, encoding: .utf8)
    }

    func buildGraph(for target: ReportItem, in directory: String, includeTests: Bool = false) async -> ReferenceGraphResult {
        let directoryURL = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        var result = ReferenceGraphResult(target: target, includesTests: includeTests, targetFound: false)
        guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            result.warnings = ["Directory does not exist: \(directory)"]
            return result
        }
        guard target.type != .parameter && target.type != .import else {
            result.warnings = ["\(target.type.rawValue.capitalized) findings do not represent independently callable declarations; inspect the enclosing declaration instead."]
            return result
        }

        let discovery = await discoverFiles(directoryURL, includeTests)
        // Canonicalize and deduplicate before parsing, including symlink aliases.
        let files = Set(discovery.files.map { $0.standardizedFileURL.resolvingSymlinksInPath() }).sorted { $0.path < $1.path }
        let sourceReader = readSource
        let parsed: [(file: URL, parsed: ParsedFile?)] = await withTaskGroup(of: (URL, ParsedFile?).self) { group in
            for file in files {
                group.addTask {
                    guard let source = try? sourceReader(file) else { return (file, nil) }
                    return (file, ParsedFile(url: file, source: source, sourceFile: Parser.parse(source: source)))
                }
            }
            var collected: [(URL, ParsedFile?)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0.path < $1.0.path }
        }
        let parsedFiles = parsed.compactMap(\.parsed)
        result.scannedFileCount = parsedFiles.count
        result.warnings = parsed.compactMap { item in
            item.parsed == nil ? "Could not read \(item.file.path); incoming references may be missing." : nil
        }
        for file in parsedFiles where file.sourceFile.hasError {
            result.warnings.append("Syntax errors in \(file.url.path); references from this file may be incomplete.")
        }
        if !includeTests && discovery.excludedTestFileCount > 0 {
            result.warnings.append("\(discovery.excludedTestFileCount) test files excluded; use --include-tests to inspect their references.")
        }

        let knownTypes = Set(parsedFiles.flatMap { typeNames(in: Syntax($0.sourceFile)) })
        let bodies: [DeclarationBody] = await withTaskGroup(of: [DeclarationBody].self) { group in
            for file in parsedFiles {
                group.addTask {
                    let visitor = ReferenceGraphVisitor(filePath: file.url.path, sourceFile: file.sourceFile, knownTypeNames: knownTypes)
                    visitor.walk(file.sourceFile)
                    return visitor.declarationBodies
                }
            }
            var collected: [DeclarationBody] = []
            for await declarations in group { collected.append(contentsOf: declarations) }
            return collected.sorted { declarationOrder($0.declaration, $1.declaration) }
        }

        let targetURL = target.file.hasPrefix("/")
            ? URL(fileURLWithPath: target.file)
            : directoryURL.appendingPathComponent(target.file)
        let targetFile = targetURL.standardizedFileURL.resolvingSymlinksInPath().path
        var matches = bodies.filter {
            $0.declaration.file == targetFile && $0.declaration.name == target.name
                && $0.declaration.line == target.line && matchesKind($0.declaration.kind, target.type)
                && (target.parentType == nil || $0.declaration.parentType == target.parentType)
        }
        if let identity = target.identity {
            var currentIdentity: DeclarationIdentity?
            if let file = parsedFiles.first(where: { $0.url.path == targetFile }) {
                let visitor = DeclarationVisitor(filePath: targetFile, protocolRequirements: [:], sourceFile: file.sourceFile)
                visitor.walk(file.sourceFile)
                currentIdentity = visitor.declarations.compactMap(\.identity).first {
                    $0.offset == identity.offset && $0.signature == identity.signature
                        && $0.enclosingTypePath == identity.enclosingTypePath
                }
            }
            matches = currentIdentity == nil ? [] : matches.filter { $0.offset == identity.offset }
        }
        guard matches.count == 1, let root = matches.first else {
            result.warnings.append(matches.isEmpty
                ? "Report location no longer identifies '\(target.name)' at \(target.file):\(target.line). Run 'unused analyze' to refresh the IDs."
                : "The report cannot distinguish declarations named '\(target.name)' on the same line. Separate them and run 'unused analyze' again.")
            return result
        }
        result.root = root.declaration
        result.targetFound = true
        if ["class", "struct", "enum", "actor", "protocol"].contains(root.declaration.kind) {
            result.warnings.append("Type dependencies show the type's own signature, not the combined bodies of its members.")
        }
        if root.declaration.kind == "subscript" {
            result.warnings.append("Subscript invocations require receiver type checking and may not appear as incoming references.")
        }

        let byName = Dictionary(grouping: bodies, by: { $0.declaration.name })
        let scopeKinds = Dictionary(grouping: bodies, by: { $0.declaration.file }).mapValues { declarations in
            Dictionary(declarations.map { ($0.offset, $0.declaration.kind) }, uniquingKeysWith: { first, _ in first })
        }
        var edges = Set<ReferenceEdge>()
        for body in bodies {
            for usage in Set(body.references) {
                let resolution = resolve(usage, from: body, byName: byName, scopeKinds: scopeKinds)
                if resolution.matches.isEmpty && body.declaration == root.declaration {
                    result.unresolved.append(usage)
                }
                for match in resolution.matches {
                    edges.insert(ReferenceEdge(source: body.declaration, target: match.declaration,
                                               usage: usage, isAmbiguous: resolution.ambiguous))
                }
            }
        }
        result.edges = edges.sorted {
            if $0.source != $1.source { return declarationOrder($0.source, $1.source) }
            if $0.target != $1.target { return declarationOrder($0.target, $1.target) }
            return usageOrder($0.usage, $1.usage)
        }

        result.unresolved.sort(by: usageOrder)
        return result
    }

    private func resolve(
        _ usage: ReferenceUsage,
        from source: DeclarationBody,
        byName: [String: [DeclarationBody]],
        scopeKinds: [String: [Int: String]]
    ) -> (matches: [DeclarationBody], ambiguous: Bool) {
        var candidates = (byName[usage.name] ?? []).filter { candidate in
            // Types/members can be referenced across files. Local functions/types must be in a visible enclosing scope.
            let localScopes = candidate.lexicalScope.filter { offset in
                let kind = scopeKinds[candidate.declaration.file]?[offset]
                return kind == nil || ["function", "initializer", "subscript", "variable", "deinitializer"].contains(kind ?? "")
            }
            let visibleScope = usage.lexicalScope
            return localScopes.isEmpty || (candidate.declaration.file == source.declaration.file
                && localScopes.allSatisfy { visibleScope.contains($0) })
        }
        let typeKinds = ["class", "struct", "enum", "actor", "protocol", "typealias", "associatedtype"]
        if usage.kind == .type {
            candidates = candidates.filter { typeKinds.contains($0.declaration.kind) }
        } else if usage.kind == .call {
            candidates = candidates.filter {
                ["function", "initializer", "subscript", "enumCase", "variable"].contains($0.declaration.kind)
                    || typeKinds.contains($0.declaration.kind)
            }
        }

        let isOperator = usage.kind == .call && usage.argumentLabels == nil && !usage.isMember
        let receiverType = usage.receiverType.flatMap { ["Any", "AnyObject"].contains($0) ? nil : $0 }
        if isOperator {
            candidates = candidates.filter { $0.declaration.kind == "function" }
        } else if let receiver = receiverType {
            candidates = candidates.filter { $0.declaration.parentType == receiver }
        } else if usage.isMember {
            // An unknown receiver is a possible match, never a confirmed name-only match.
            candidates = candidates.filter { $0.declaration.parentType != nil }
        } else {
            let sameType = candidates.filter {
                source.declaration.parentType != nil && $0.declaration.parentType == source.declaration.parentType
            }
            let locals = candidates.filter { candidate in
                candidate.declaration.file == source.declaration.file
                    && candidate.lexicalScope.contains { scopeKinds[candidate.declaration.file]?[$0] == "function" }
            }
            if !locals.isEmpty {
                let depth = locals.map { $0.lexicalScope.count }.max() ?? 0
                candidates = locals.filter { $0.lexicalScope.count == depth }
            } else if !sameType.isEmpty {
                candidates = sameType
            } else {
                candidates = candidates.filter { $0.declaration.parentType == nil }
            }
        }

        var ambiguous = (usage.isMember && receiverType == nil) || isOperator
        if let labels = usage.argumentLabels {
            let compatible = candidates.filter { accepts(labels, callable: $0) }
            if !compatible.isEmpty {
                candidates = compatible
            } else if !candidates.isEmpty {
                // Trailing closures, implicit conversions and macros may need semantic resolution.
                ambiguous = true
            }
        }
        ambiguous = ambiguous || candidates.count > 1

        // A constructor refers both to its type and, when present, an initializer implementation.
        if usage.kind == .call {
            let constructedTypes = candidates.filter { ["class", "struct", "enum", "actor"].contains($0.declaration.kind) }
            for type in constructedTypes {
                let typeName = [type.declaration.parentType, type.declaration.name].compactMap { $0 }.joined(separator: ".")
                let initializers = (byName["init"] ?? []).filter {
                    guard $0.declaration.parentType == typeName else { return false }
                    let declaredInType = $0.declaration.file == type.declaration.file && $0.lexicalScope.last == type.offset
                    let declaredInExtension = $0.lexicalScope.isEmpty && type.lexicalScope.allSatisfy {
                        ["class", "struct", "enum", "actor", "protocol"].contains(scopeKinds[type.declaration.file]?[$0] ?? "")
                    }
                    return declaredInType || declaredInExtension
                }
                let compatible = initializers.filter { accepts(usage.argumentLabels ?? [], callable: $0) }
                let matches = compatible.isEmpty ? initializers : compatible
                if matches.count > 1 || (!matches.isEmpty && compatible.isEmpty) { ambiguous = true }
                candidates.append(contentsOf: matches)
            }
        }
        return (candidates, ambiguous)
    }

    private func accepts(_ labels: [String], callable: DeclarationBody) -> Bool {
        guard let parameters = callable.parameterLabels else { return true }
        func match(_ parameter: Int, _ argument: Int) -> Bool {
            if parameter == parameters.count { return argument == labels.count }
            if callable.defaultedParameterIndices.contains(parameter), match(parameter + 1, argument) {
                return true
            }
            if callable.variadicParameterIndex == parameter {
                if match(parameter + 1, argument) { return true }
                var index = argument
                while index < labels.count && labels[index] == (index == argument ? parameters[parameter] : "_") {
                    index += 1
                    if match(parameter + 1, index) { return true }
                }
                return false
            }
            return argument < labels.count && labels[argument] == parameters[parameter] && match(parameter + 1, argument + 1)
        }
        return match(0, 0)
    }

    private func matchesKind(_ kind: String, _ type: DeclarationType) -> Bool {
        switch type {
        case .function: ["function", "initializer", "subscript"].contains(kind)
        case .class: ["class", "struct", "enum", "actor"].contains(kind)
        default: kind == type.rawValue
        }
    }

    private func typeNames(in node: Syntax, parentType: String? = nil) -> [String] {
        let name: String?
        switch node.as(SyntaxEnum.self) {
        case .classDecl(let declaration): name = declaration.name.identifierName
        case .structDecl(let declaration): name = declaration.name.identifierName
        case .enumDecl(let declaration): name = declaration.name.identifierName
        case .actorDecl(let declaration): name = declaration.name.identifierName
        case .protocolDecl(let declaration): name = declaration.name.identifierName
        case .typeAliasDecl(let declaration): name = declaration.name.identifierName
        default: name = nil
        }
        let fullName = name.map { [parentType, $0].compactMap { $0 }.joined(separator: ".") }
        let context = node.as(ExtensionDeclSyntax.self).map { SwiftTypeName.canonical($0.extendedType) }
            ?? (node.is(TypeAliasDeclSyntax.self) ? parentType : fullName ?? parentType)
        return (name.map { [$0] } ?? []) + (fullName.map { [$0] } ?? [])
            + node.children(viewMode: .sourceAccurate).flatMap { typeNames(in: $0, parentType: context) }
    }

    private func declarationOrder(_ lhs: DeclarationReference, _ rhs: DeclarationReference) -> Bool {
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.kind < rhs.kind
    }

    private func usageOrder(_ lhs: ReferenceUsage, _ rhs: ReferenceUsage) -> Bool {
        if lhs.file != rhs.file { return lhs.file < rhs.file }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
