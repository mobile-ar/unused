import Foundation
import SwiftParser
import Testing

@testable import unused

struct ExplicitReferenceSafetyIntegrationTests {
    private func withProject(
        _ sources: [String: String],
        verify: (Report, [Declaration], URL) throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplicitReferenceSafety-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var declarations: [Declaration] = []
        let files = try sources.sorted(by: { $0.key < $1.key }).map { entry in
            let file = directory.appendingPathComponent(entry.key)
            try entry.value.write(to: file, atomically: true, encoding: .utf8)
            let sourceFile = Parser.parse(source: entry.value)
            try #require(!sourceFile.hasError, "Fixture \(entry.key) must parse without errors")
            let visitor = DeclarationVisitor(
                filePath: file.path, protocolRequirements: [:], sourceFile: sourceFile,
                moduleName: "ExplicitReferenceSafetyFixtures"
            )
            visitor.walk(sourceFile)
            declarations.append(contentsOf: visitor.declarations)
            return file
        }
        try await typecheck(files, in: directory)

        let analyzer = SwiftAnalyzer(
            directory: directory.path,
            swiftInterfaceClient: SwiftInterfaceClient(moduleInterfaceProvider: { _ in "" }),
            moduleName: "ExplicitReferenceSafetyFixtures",
            progressTrackerFactory: { total, prefix in
                ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
            }
        )
        let report = await analyzer.analyzeFiles(files)
        try verify(report, declarations, directory)

        // Read the analyzer's output, rather than writing a replacement report in the test.
        try #require(ReportService.reportExists(in: directory.path))
        let saved = try ReportService.read(from: directory.path)
        #expect(saved.unused == report.unused)
        #expect(saved.excluded == report.excluded)
        #expect(saved.warnings == report.warnings)
        #expect(saved.options == report.options)
        #expect(saved.summary == report.summary)
        #expect(saved.version == report.version)
        try verify(saved, declarations, directory)
    }

    private func typecheck(_ files: [URL], in directory: URL) async throws {
        let diagnosticsURL = directory.appendingPathComponent("typecheck.log")
        try Data().write(to: diagnosticsURL)
        let output = try FileHandle(forWritingTo: diagnosticsURL)
        defer { try? output.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-typecheck", "-module-name", "ExplicitReferenceSafetyFixtures"]
            + files.map(\.path)
        process.currentDirectoryURL = directory
        // A file avoids pipe-buffer deadlocks if the compiler emits many diagnostics.
        process.standardOutput = output
        process.standardError = output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let diagnostics = try String(contentsOf: diagnosticsURL, encoding: .utf8)
        try #require(status == 0, "Fixture typechecking failed:\n\(diagnostics)")
    }

    private func matches(
        _ identity: DeclarationIdentity?,
        name: String,
        owner: String,
        kind: MemberKind,
        labels: [String]?,
        parameterTypes: [String]?
    ) -> Bool {
        guard let identity, identity.isTypeMember, identity.ownerName == owner,
            identity.signature.name == name, identity.signature.kind == kind
        else { return false }
        if let labels, identity.signature.parameterLabels != labels { return false }
        if let parameterTypes, identity.signature.parameterTypes != parameterTypes { return false }
        return true
    }

    @discardableResult
    private func requireUsed(
        _ report: Report,
        declarations: [Declaration],
        name: String,
        owner: String,
        kind: MemberKind = .function,
        labels: [String]? = nil,
        parameterTypes: [String]? = nil
    ) throws -> [DeclarationIdentity] {
        let identities = declarations.compactMap(\.identity).filter {
            matches($0, name: name, owner: owner, kind: kind, labels: labels, parameterTypes: parameterTypes)
        }
        try #require(!identities.isEmpty, "Fixture must declare \(owner).\(name)")
        for identity in identities {
            #expect(!report.unused.contains { $0.identity == identity })
            #expect(!report.excluded.allItems.contains { $0.identity == identity })
        }
        return identities
    }

    @discardableResult
    private func requireUnused(
        _ report: Report,
        name: String,
        owner: String,
        kind: MemberKind = .function,
        labels: [String]? = nil,
        parameterTypes: [String]? = nil,
        reason: ExclusionReason = .none
    ) throws -> ReportItem {
        let item = try #require(
            report.unused.first {
                matches($0.identity, name: name, owner: owner, kind: kind, labels: labels, parameterTypes: parameterTypes)
            },
            "Expected unused \(owner).\(name) (kind: \(kind), labels: \(String(describing: labels)))"
        )
        #expect(item.exclusionReason == reason)
        #expect(!report.excluded.allItems.contains { $0.identity == item.identity })
        return item
    }

    private func requireWitness(_ report: Report, name: String, owner: String) throws {
        let item = try #require(
            report.excluded.protocolImplementations.first {
                matches($0.identity, name: name, owner: owner, kind: .function, labels: [], parameterTypes: [])
            })
        #expect(item.exclusionReason == .protocolImplementation)
        #expect(!report.unused.contains { $0.identity == item.identity })
    }

    @Test(arguments: [
        "_ = Item(value: 1)",
        "_ = Item.init(value: 1)",
        "let item: Item = .init(value: 1); _ = item",

        "let type: Item.Type = Item.self; _ = type.init(value: 1)"
    ])
    func constructorSyntaxUsesOnlyCompatibleLabels(_ call: String) async throws {
        try await withProject([
            "main.swift": """
            struct Item {}
            extension Item {
                init(value: Int) { _ = value }
                init(other: Int) { _ = other }
                init(value: Int, required: Int) { _ = (value, required) }
            }
            struct Other {}
            extension Other { init(value: Int) { _ = value } }
            \(call)
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["value"])
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["other"])
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["value", "required"])
            try requireUnused(report, name: "init", owner: "Other", kind: .initializer, labels: ["value"])
        }
    }

    @Test
    func constructorsAcceptOmittedDefaultsVariadicsAndTrailingClosures() async throws {
        try await withProject([
            "main.swift": """
            struct Item {}
            extension Item {
                init(value: Int, mode: Int = 0) { _ = (value, mode) }
                init(prefix: Int = 0, payload: Int) { _ = (prefix, payload) }
                init(values: Int..., offset: Int = 0) { _ = (values, offset) }
                init(completion: () -> Void) { completion() }
                init(other: Int) { _ = other }
                init(value: Int, required: Int) { _ = (value, required) }
            }
            _ = Item(value: 1)
            _ = Item(payload: 2)
            _ = Item(values: 1, 2, 3)
            _ = Item(offset: 4)
            _ = Item { }
            """
        ]) { report, declarations, _ in
            let defaulted = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["value", "mode"]
            )
            #expect(defaulted.first?.signature.defaultParameterIndices == [1])
            let leadingDefault = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["prefix", "payload"]
            )
            #expect(leadingDefault.first?.signature.defaultParameterIndices == [0])
            let variadic = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["values", "offset"]
            )
            #expect(variadic.first?.signature.variadicParameterIndices == [0])
            #expect(variadic.first?.signature.defaultParameterIndices == [1])
            try requireUsed(report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["completion"])
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["other"])
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["value", "required"])
        }
    }

    @Test
    func subscriptsAcceptCompatibleLabelsDefaultsAndVariadics() async throws {
        try await withProject([
            "main.swift": """
            struct Lookup {
                subscript(index index: Int, stride stride: Int = 1) -> Int { index + stride }
                subscript(prefix prefix: Int = 0, key key: Int) -> Int { prefix + key }
                subscript(values values: Int..., offset offset: Int = 0) -> Int { values.count + offset }
                subscript(other index: Int) -> Int { index }
                subscript(index index: Int, required required: Int) -> Int { index + required }
            }
            struct Other {
                subscript(index index: Int, stride stride: Int = 1) -> Int { index + stride }
            }
            func inspect(_ annotated: Lookup, _ optional: Lookup?) {
                _ = annotated[index: 1]
                _ = optional?[key: 2]
                _ = optional![values: 1, 2, 3]
                _ = (annotated)[offset: 4]
            }
            let inferred = Lookup()
            _ = inferred[index: 1, stride: 2]
            inspect(inferred, inferred)
            """
        ]) { report, declarations, _ in
            let defaulted = try requireUsed(
                report, declarations: declarations, name: "subscript", owner: "Lookup", kind: .subscript, labels: ["index", "stride"]
            )
            #expect(defaulted.first?.signature.defaultParameterIndices == [1])
            let leadingDefault = try requireUsed(
                report, declarations: declarations, name: "subscript", owner: "Lookup", kind: .subscript, labels: ["prefix", "key"]
            )
            #expect(leadingDefault.first?.signature.defaultParameterIndices == [0])
            let variadic = try requireUsed(
                report, declarations: declarations, name: "subscript", owner: "Lookup", kind: .subscript, labels: ["values", "offset"]
            )
            #expect(variadic.first?.signature.variadicParameterIndices == [0])
            try requireUnused(report, name: "subscript", owner: "Lookup", kind: .subscript, labels: ["other"])
            try requireUnused(report, name: "subscript", owner: "Lookup", kind: .subscript, labels: ["index", "required"])
            try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: ["index", "stride"])
        }
    }

    @Test
    func compatibleTypeOverloadsAreRetainedWithoutSemanticOverloadSelection() async throws {
        try await withProject([
            "main.swift": """
            struct Item {
                subscript(index index: Int) -> Int { index }
                subscript(index index: Double) -> Int { Int(index) }
                subscript(other index: Int) -> Int { index }
            }
            extension Item {
                init(value: Int) { _ = value }
                init(value: Double) { _ = value }
                init(other: Int) { _ = other }
            }
            let item = Item(value: 1)
            _ = item[index: 2]
            """
        ]) { report, declarations, _ in
            let constructors = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Item", kind: .initializer, labels: ["value"]
            )
            #expect(constructors.count == 2)
            #expect(Set(constructors.map(\.signature.parameterTypes)) == [["Int"], ["Double"]])
            let subscripts = try requireUsed(
                report, declarations: declarations, name: "subscript", owner: "Item", kind: .subscript, labels: ["index"]
            )
            #expect(subscripts.count == 2)
            #expect(Set(subscripts.map(\.signature.parameterTypes)) == [["Int"], ["Double"]])
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["other"])
            try requireUnused(report, name: "subscript", owner: "Item", kind: .subscript, labels: ["other"])
        }
    }

    @Test(arguments: [
        "do { let receiver = B(); receiver.inside(); _ = receiver[inside: 0] }",
        "if flag { let receiver = B(); receiver.inside(); _ = receiver[inside: 0] }",
        "if flag {} else { let receiver = B(); receiver.inside(); _ = receiver[inside: 0] }",
        "if let receiver = optional { receiver.inside(); _ = receiver[inside: 0] }",
        "do { guard let receiver = optional else { return }; receiver.inside(); _ = receiver[inside: 0] }",
        "do { try attempt() } catch { let receiver = B(); receiver.inside(); _ = receiver[inside: 0] }",
        "switch flag { case true: let receiver = B(); receiver.inside(); _ = receiver[inside: 0]; case false: break }"
    ])
    func lexicalScopesRestoreOuterReceiverAfterTypedShadows(_ body: String) async throws {
        let owners = ["A", "B", "Other"].map { owner in
            """
            struct \(owner) {
                func before() {}
                func inside() {}
                func after() {}
                func neverCalled() {}
                subscript(before index: Int) -> Int { index }
                subscript(inside index: Int) -> Int { index }
                subscript(after index: Int) -> Int { index }
                subscript(unused index: Int) -> Int { index }
            }
            """
        }.joined(separator: "\n")
        try await withProject([
            "Owners.swift": owners,
            "main.swift": """
            func attempt() throws {}
            func inspect(_ receiver: A, _ optional: B?, _ flag: Bool) {
                receiver.before()
                _ = receiver[before: 0]
                \(body)
                receiver.after()
                _ = receiver[after: 0]
            }
            inspect(A(), B(), true)
            """
        ]) { report, declarations, _ in
            for name in ["before", "after"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "A")
                try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: [name])
                try requireUnused(report, name: name, owner: "B")
                try requireUnused(report, name: "subscript", owner: "B", kind: .subscript, labels: [name])
            }
            try requireUsed(report, declarations: declarations, name: "inside", owner: "B")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "B", kind: .subscript, labels: ["inside"])
            try requireUnused(report, name: "inside", owner: "A")
            try requireUnused(report, name: "subscript", owner: "A", kind: .subscript, labels: ["inside"])
            for owner in ["A", "B", "Other"] {
                try requireUnused(report, name: "neverCalled", owner: owner)
                try requireUnused(report, name: "subscript", owner: owner, kind: .subscript, labels: ["unused"])
            }
            for name in ["before", "inside", "after"] {
                try requireUnused(report, name: name, owner: "Other")
                try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: [name])
            }
        }
    }

    @Test(arguments: [
        "if let receiver = optional { receiver.inside() } else { receiver.sibling(); _ = receiver[sibling: 0] }",
        "switch flag { case true: let receiver = B(); receiver.inside(); case false: receiver.sibling(); _ = receiver[sibling: 0] }",
        "do { let receiver = B(); receiver.inside(); try attempt() } catch { receiver.sibling(); _ = receiver[sibling: 0] }"
    ])
    func siblingBranchesDoNotInheritEarlierBranchBindings(_ body: String) async throws {
        try await withProject([
            "main.swift": """
            struct A {
                func sibling() {}
                func inside() {}
                subscript(sibling index: Int) -> Int { index }
            }
            struct B {
                func sibling() {}
                func inside() {}
                subscript(sibling index: Int) -> Int { index }
            }
            func attempt() throws {}
            func inspect(_ receiver: A, _ optional: B?, _ flag: Bool) {
                \(body)
            }
            inspect(A(), B(), true)
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "inside", owner: "B")
            try requireUsed(report, declarations: declarations, name: "sibling", owner: "A")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: ["sibling"])
            try requireUnused(report, name: "inside", owner: "A")
            try requireUnused(report, name: "sibling", owner: "B")
            try requireUnused(report, name: "subscript", owner: "B", kind: .subscript, labels: ["sibling"])
        }
    }

    @Test
    func guardElseUsesOuterReceiverAndSuccessBindingPersistsUntilBlockExit() async throws {
        try await withProject([
            "main.swift": """
            struct A {
                func failure() {}
                func success() {}
                func after() {}
                subscript(failure index: Int) -> Int { index }
                subscript(success index: Int) -> Int { index }
                subscript(after index: Int) -> Int { index }
            }
            struct B {
                func failure() {}
                func success() {}
                func after() {}
                subscript(failure index: Int) -> Int { index }
                subscript(success index: Int) -> Int { index }
                subscript(after index: Int) -> Int { index }
            }
            func inspect(_ receiver: A, _ optional: B?) {
                do {
                    guard let receiver = optional else {
                        receiver.failure()
                        _ = receiver[failure: 0]
                        return
                    }
                    receiver.success()
                    _ = receiver[success: 0]
                }
                receiver.after()
                _ = receiver[after: 0]
            }
            inspect(A(), B())
            """
        ]) { report, declarations, _ in
            for name in ["failure", "after"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "A")
                try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: [name])
                try requireUnused(report, name: name, owner: "B")
                try requireUnused(report, name: "subscript", owner: "B", kind: .subscript, labels: [name])
            }
            try requireUsed(report, declarations: declarations, name: "success", owner: "B")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "B", kind: .subscript, labels: ["success"])
            try requireUnused(report, name: "success", owner: "A")
            try requireUnused(report, name: "subscript", owner: "A", kind: .subscript, labels: ["success"])
        }
    }

    @Test(arguments: [
        "do { let receiver = identity(B()); receiver.inside(); _ = receiver[inside: 0] }",
        "switch Optional(B()) { case let .some(receiver): receiver.inside(); _ = receiver[inside: 0]; case .none: break }",
        "do { try attempt() } catch { let receiver = identity(B()); receiver.inside(); _ = receiver[inside: 0] }",
        "do { try attempt() } catch let receiver { receiver.inside(); _ = receiver[inside: 0] }"
    ])
    func unknownShadowsRetainPlausibleMembersWithoutUsingOuterReceiverType(_ body: String) async throws {
        let owners = ["A", "B", "Other"].map { owner in
            """
            struct \(owner) {
                func inside() {}
                func after() {}
                func neverCalled() {}
                subscript(inside index: Int) -> Int { index }
                subscript(after index: Int) -> Int { index }
                subscript(unused index: Int) -> Int { index }
            }
            """
        }.joined(separator: "\n")
        try await withProject([
            "Owners.swift": owners,
            "main.swift": """
            func identity<T>(_ value: T) -> T { value }
            extension Error {
                func inside() {}
                subscript(inside index: Int) -> Int { index }
            }
            func attempt() throws {}
            func inspect(_ receiver: A) {
                \(body)
                receiver.after()
                _ = receiver[after: 0]
            }
            inspect(A())
            """
        ]) { report, declarations, _ in
            for owner in ["A", "B", "Other"] {
                try requireUsed(report, declarations: declarations, name: "inside", owner: owner)
                try requireUsed(report, declarations: declarations, name: "subscript", owner: owner, kind: .subscript, labels: ["inside"])
                try requireUnused(report, name: "neverCalled", owner: owner)
                try requireUnused(report, name: "subscript", owner: owner, kind: .subscript, labels: ["unused"])
            }
            try requireUsed(report, declarations: declarations, name: "after", owner: "A")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: ["after"])
            for owner in ["B", "Other"] {
                try requireUnused(report, name: "after", owner: owner)
                try requireUnused(report, name: "subscript", owner: owner, kind: .subscript, labels: ["after"])
            }
        }
    }

    @Test(arguments: [
        "if let value { _ = value }",
        "guard let value else { return }; _ = value",
        "while let value { _ = value; break }"
    ])
    func shorthandOptionalBindingsReadPropertiesButNotShadowedProperties(_ body: String) async throws {
        try await withProject([
            "main.swift": """
            struct Subject {
                var value: Int? = nil
                var localOnly: Int? = nil
                var restored: Int? = nil
                var writeOnly: Int? = nil
                var untouched: Int? = nil
                mutating func inspect() {
                    value = 1
                    localOnly = 2
                    restored = 3
                    writeOnly = 4
                    do {
                        let localOnly: Int? = 5
                        \(body.replacing("value", with: "localOnly"))
                    }
                    do {
                        let restored: Int? = 6
                        _ = restored
                    }
                    _ = restored
                    \(body)
                }
            }
            var subject = Subject()
            subject.inspect()
            """
        ]) { report, declarations, _ in
            for name in ["value", "restored"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "Subject", kind: .property)
            }
            for name in ["localOnly", "writeOnly"] {
                try requireUnused(report, name: name, owner: "Subject", kind: .property, reason: .writeOnly)
            }
            try requireUnused(report, name: "untouched", owner: "Subject", kind: .property)
        }
    }

    @Test
    func crossFileInheritanceAndChainedAliasesResolveProviderOwners() async throws {
        try await withProject([
            "Base.swift": """
            class Base {
                init(seed: Int = 0) { _ = seed }
                init(unused: Int) { _ = unused }
                func directMember() {}
                func aliasMember() {}
                func unusedMember() {}
                var directValue: Int { 1 }
                var aliasValue: Int { 2 }
                subscript(index index: Int) -> Int { index }
                subscript(key key: String) -> Int { key.count }
                subscript(unused index: Int) -> Int { index }
            }
            """,
            "Derived.swift": """
            class Derived: Base {}
            typealias Alias = Derived
            typealias ChainedAlias = Alias
            """,
            "Other.swift": """
            class Other {
                init(seed: Int = 0) { _ = seed }
                func directMember() {}
                func aliasMember() {}
                var directValue: Int { 1 }
                var aliasValue: Int { 2 }
                subscript(index index: Int) -> Int { index }
                subscript(key key: String) -> Int { key.count }
            }
            """,
            "main.swift": """
            let direct = Derived(seed: 1)
            direct.directMember()
            _ = direct.directValue
            _ = direct[index: 0]
            let aliased = ChainedAlias.init(seed: 2)
            aliased.aliasMember()
            _ = aliased.aliasValue
            _ = aliased[key: "key"]
            """
        ]) { report, declarations, directory in
            let constructors = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Base", kind: .initializer, labels: ["seed"]
            )
            #expect(constructors.first?.file == directory.appendingPathComponent("Base.swift").path)
            try requireUnused(report, name: "init", owner: "Base", kind: .initializer, labels: ["unused"])
            try requireUnused(report, name: "init", owner: "Other", kind: .initializer, labels: ["seed"])
            for name in ["directMember", "aliasMember"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "Base")
                try requireUnused(report, name: name, owner: "Other")
            }
            for name in ["directValue", "aliasValue"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "Base", kind: .property)
                try requireUnused(report, name: name, owner: "Other", kind: .property)
            }
            for label in ["index", "key"] {
                try requireUsed(report, declarations: declarations, name: "subscript", owner: "Base", kind: .subscript, labels: [label])
                try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: [label])
            }
            try requireUnused(report, name: "unusedMember", owner: "Base")
            try requireUnused(report, name: "subscript", owner: "Base", kind: .subscript, labels: ["unused"])
        }
    }

    @Test
    func crossFileProtocolExtensionHelperIsUsedThroughConcreteConformer() async throws {
        try await withProject([
            "P.swift": """
            protocol P { func required() }
            """,
            "P+Helpers.swift": """
            extension P {
                func helper() {}
                func unusedHelper() {}
            }
            """,
            "Concrete.swift": """
            struct Concrete: P { func required() {} }
            struct Other {
                func helper() {}
                func unusedHelper() {}
            }
            """,
            "main.swift": """
            let concrete = Concrete()
            concrete.helper()
            """
        ]) { report, declarations, directory in
            let helper = try requireUsed(report, declarations: declarations, name: "helper", owner: "P")
            #expect(helper.first?.file == directory.appendingPathComponent("P+Helpers.swift").path)
            try requireWitness(report, name: "required", owner: "Concrete")
            try requireUnused(report, name: "unusedHelper", owner: "P")
            try requireUnused(report, name: "helper", owner: "Other")
            try requireUnused(report, name: "unusedHelper", owner: "Other")
            #expect(report.warnings.isEmpty)
        }
    }

    @Test
    func escapedNestedOwnersAndNamespaceAliasesRemainDistinctAcrossFiles() async throws {
        try await withProject([
            "Namespaces.swift": """
            enum `repeat` { struct `switch` {} }
            enum `while` { struct `switch` {} }
            typealias NamespaceAlias = `repeat`
            typealias ItemAlias = NamespaceAlias.`switch`
            typealias ChainedAlias = ItemAlias
            """,
            "Selected.swift": """
            extension `repeat`.`switch` {
                init(`default` value: Int) { _ = value }
                init(other: Int) { _ = other }
                subscript(`case` index: Int) -> Int { index }
                subscript(other index: Int) -> Int { index }
                func `return`() {}
                func unusedMember() {}
            }
            """,
            "Unrelated.swift": """
            extension `while`.`switch` {
                init(`default` value: Int) { _ = value }
                subscript(`case` index: Int) -> Int { index }
                func `return`() {}
            }
            """,
            "main.swift": """
            _ = `repeat`.`switch`.init(`default`: 1)
            let receiver = ChainedAlias(`default`: 2)
            _ = receiver[`case`: 0]
            receiver.`return`()
            """
        ]) { report, declarations, directory in
            let constructors = try requireUsed(
                report, declarations: declarations, name: "init", owner: "repeat.switch", kind: .initializer, labels: ["default"]
            )
            #expect(constructors.first?.enclosingTypePath == ["repeat", "switch"])
            #expect(constructors.first?.moduleName == "ExplicitReferenceSafetyFixtures")
            #expect(constructors.first?.file == directory.appendingPathComponent("Selected.swift").path)
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "repeat.switch", kind: .subscript, labels: ["case"])
            try requireUsed(report, declarations: declarations, name: "return", owner: "repeat.switch")
            try requireUnused(report, name: "init", owner: "repeat.switch", kind: .initializer, labels: ["other"])
            try requireUnused(report, name: "subscript", owner: "repeat.switch", kind: .subscript, labels: ["other"])
            try requireUnused(report, name: "unusedMember", owner: "repeat.switch")
            try requireUnused(report, name: "init", owner: "while.switch", kind: .initializer, labels: ["default"])
            try requireUnused(report, name: "subscript", owner: "while.switch", kind: .subscript, labels: ["case"])
            try requireUnused(report, name: "return", owner: "while.switch")
        }
    }

    @Test(arguments: ["Base", "Child", "Alias"])
    func membersDeclaredOnAliasExtensionsResolveThroughConcreteAndInheritedOwners(_ receiverType: String) async throws {
        try await withProject([
            "Owners.swift": """
            class Base {}
            class Child: Base {}
            struct Other {
                func work() {}
                subscript(index index: Int) -> Int { index }
            }
            """,
            "Alias+Members.swift": """
            typealias Alias = Base
            extension Alias {
                func work() {}
                func unusedMember() {}
                subscript(index index: Int) -> Int { index }
                subscript(other index: Int) -> Int { index }
            }
            """,
            "main.swift": """
            let receiver = \(receiverType)()
            receiver.work()
            _ = receiver[index: 1]
            """
        ]) { report, declarations, directory in
            let members = try requireUsed(report, declarations: declarations, name: "work", owner: "Alias")
            #expect(members.first?.file == directory.appendingPathComponent("Alias+Members.swift").path)
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "Alias", kind: .subscript, labels: ["index"])
            try requireUnused(report, name: "unusedMember", owner: "Alias")
            try requireUnused(report, name: "subscript", owner: "Alias", kind: .subscript, labels: ["other"])
            try requireUnused(report, name: "work", owner: "Other")
            try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: ["index"])
        }
    }

    @Test
    func trailingClosuresRetainInitializersWithFunctionAliasesAndEnclosingGenericParameters() async throws {
        try await withProject([
            "Callbacks.swift": """
            typealias Completion = () -> Void
            struct Item {}
            extension Item {
                init(completion: Completion) { completion() }
                init(other: Int) { _ = other }
                init(completion: Completion, required: Int) { completion(); _ = required }
            }
            struct Box<Callback> {}
            extension Box {
                init(callback: Callback) { _ = callback }
                init(other: Int) { _ = other }
                init(callback: Callback, required: Int) { _ = (callback, required) }
            }
            struct Other {}
            extension Other {
                init(completion: Completion) { completion() }
            }
            """,
            "main.swift": """
            _ = Item { }
            _ = Box<Completion> { }
            """
        ]) { report, declarations, _ in
            try requireUsed(
                report, declarations: declarations, name: "init", owner: "Item", kind: .initializer,
                labels: ["completion"], parameterTypes: ["Completion"]
            )
            try requireUsed(
                report, declarations: declarations, name: "init", owner: "Box", kind: .initializer,
                labels: ["callback"], parameterTypes: ["Callback"]
            )
            for owner in ["Item", "Box"] {
                try requireUnused(report, name: "init", owner: owner, kind: .initializer, labels: ["other"])
            }
            try requireUnused(report, name: "init", owner: "Item", kind: .initializer, labels: ["completion", "required"])
            try requireUnused(report, name: "init", owner: "Box", kind: .initializer, labels: ["callback", "required"])
            try requireUnused(report, name: "init", owner: "Other", kind: .initializer, labels: ["completion"])
        }
    }

    @Test(arguments: ["Holder", "ChildHolder"])
    func crossFileAndInheritedReceiverPropertiesHideSameNamedGlobals(_ holderType: String) async throws {
        try await withProject([
            "Holders.swift": """
            struct Right {
                func work() {}
                func neverCalled() {}
                subscript(index index: Int) -> Int { index }
                subscript(unused index: Int) -> Int { index }
            }
            struct Wrong {
                func work() {}
                func neverCalled() {}
                subscript(index index: Int) -> Int { index }
                subscript(unused index: Int) -> Int { index }
            }
            class Holder { var receiver: Right = Right() }
            class ChildHolder: Holder {}
            """,
            "Holders+Exercise.swift": """
            let receiver = Wrong()
            extension \(holderType) {
                func exercise() {
                    receiver.work()
                    _ = receiver[index: 1]
                }
            }
            """,
            "main.swift": """
            let holder = \(holderType)()
            holder.exercise()
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "receiver", owner: "Holder", kind: .property)
            try requireUsed(report, declarations: declarations, name: "work", owner: "Right")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "Right", kind: .subscript, labels: ["index"])
            // Cross-file property metadata may leave the receiver unknown; retaining
            // Wrong's same-named candidates is safe, unlike retaining only Wrong.
            for owner in ["Right", "Wrong"] {
                try requireUnused(report, name: "neverCalled", owner: owner)
                try requireUnused(report, name: "subscript", owner: owner, kind: .subscript, labels: ["unused"])
            }
        }
    }

    @Test
    func crossFileGenericExtensionDoesNotResolveTypeParameterAsUnrelatedNominalType() async throws {
        try await withProject([
            "Box.swift": """
            protocol P { func required() }
            extension P {
                func helper() {}
                func unusedHelper() {}
            }
            struct Concrete: P { func required() {} }
            struct Box<T: P> {}
            struct T {
                func helper() {}
                func unusedMember() {}
            }
            """,
            "Box+Exercise.swift": """
            extension Box {
                func exercise(_ x: T) { x.helper() }
            }
            """,
            "main.swift": """
            let box = Box<Concrete>()
            box.exercise(Concrete())
            """
        ]) { report, declarations, directory in
            let helpers = try requireUsed(report, declarations: declarations, name: "helper", owner: "P")
            #expect(helpers.first?.file == directory.appendingPathComponent("Box.swift").path)
            try requireWitness(report, name: "required", owner: "Concrete")
            // Generic receiver inference may conservatively retain T.helper too.
            try requireUnused(report, name: "unusedHelper", owner: "P")
            try requireUnused(report, name: "unusedMember", owner: "T")
        }
    }

    @Test(arguments: [
        "class func make() -> Self { Self.init(seed: 1) }",
        "static func make() -> Self { self.init(seed: 1) }"
    ])
    func dynamicRequiredInitializersRetainSubclassProvidersForSelfAndStaticSelf(_ factory: String) async throws {
        try await withProject([
            "main.swift": """
            class Base {
                required init(seed: Int = 0) { _ = seed }
                init(unused: Int) { _ = unused }
                \(factory)
            }
            class Child: Base {
                required init(seed: Int) { _ = seed; super.init() }
                init(other: Int) { _ = other; super.init() }
            }
            class Other {
                init(seed: Int) { _ = seed }
            }
            _ = Child.make()
            """
        ]) { report, declarations, _ in
            let base = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Base", kind: .initializer, labels: ["seed"]
            )
            #expect(base.first?.signature.defaultParameterIndices == [0])
            let child = try requireUsed(
                report, declarations: declarations, name: "init", owner: "Child", kind: .initializer, labels: ["seed"]
            )
            #expect(child.first?.signature.defaultParameterIndices.isEmpty == true)
            try requireUsed(report, declarations: declarations, name: "make", owner: "Base")
            try requireUnused(report, name: "init", owner: "Base", kind: .initializer, labels: ["unused"])
            try requireUnused(report, name: "init", owner: "Child", kind: .initializer, labels: ["other"])
            try requireUnused(report, name: "init", owner: "Other", kind: .initializer, labels: ["seed"])
        }
    }

    @Test(arguments: ["locals", "captures", "parameters"])
    func expressionPatternClosuresPreserveReceiverAndCaptureScopes(_ scenario: String) async throws {
        let expression: String
        switch scenario {
        case "locals":
            expression = """
                evaluate({
                    let receiver = B()
                    receiver.inside()
                    _ = receiver[inside: 1]
                    return 0
                })
                """
        case "captures":
            expression = """
                evaluate({ [receiver = other, capturedReceiver = receiver] in
                    receiver.inside()
                    capturedReceiver.captured()
                    _ = receiver[inside: 1]
                    _ = capturedReceiver[captured: 1]
                    return 0
                })
                """
        default:
            expression = """
                evaluateB({ (receiver: B) in
                    receiver.inside()
                    _ = receiver[inside: 1]
                    return 0
                })
                """
        }
        let patternExpression = scenario == "captures" ? "evaluate(patternOperation)" : expression
        let patternSetup = scenario == "captures" ? "let patternOperation = " + expression.dropFirst("evaluate(".count).dropLast() : ""
        let owners = ["A", "B", "Other"].map { owner in
            """
            struct \(owner) {
                func inside() {}
                func captured() {}
                func afterPattern() {}
                func afterSwitch() {}
                func neverCalled() {}
                subscript(inside index: Int) -> Int { index }
                subscript(captured index: Int) -> Int { index }
                subscript(after index: Int) -> Int { index }
            }
            """
        }.joined(separator: "\n")
        try await withProject([
            "Owners.swift": owners,
            "main.swift": """
            func evaluate(_ operation: () -> Int) -> Int { operation() }
            func evaluateB(_ operation: (B) -> Int) -> Int { operation(B()) }
            func exercise(_ receiver: A, _ other: B, _ input: Int) {
                \(patternSetup)
                switch input {
                case \(patternExpression):
                    receiver.afterPattern()
                    _ = receiver[after: 1]
                default: break
                }
                receiver.afterSwitch()
            }
            exercise(A(), B(), 0)
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "inside", owner: "B")
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "B", kind: .subscript, labels: ["inside"])
            try requireUnused(report, name: "inside", owner: "A")
            try requireUnused(report, name: "subscript", owner: "A", kind: .subscript, labels: ["inside"])
            for name in ["afterPattern", "afterSwitch"] {
                try requireUsed(report, declarations: declarations, name: name, owner: "A")
                try requireUnused(report, name: name, owner: "B")
                try requireUnused(report, name: name, owner: "Other")
            }
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: ["after"])
            try requireUnused(report, name: "subscript", owner: "B", kind: .subscript, labels: ["after"])
            if scenario == "captures" {
                try requireUsed(report, declarations: declarations, name: "captured", owner: "A")
                try requireUsed(report, declarations: declarations, name: "subscript", owner: "A", kind: .subscript, labels: ["captured"])
            } else {
                try requireUnused(report, name: "captured", owner: "A")
                try requireUnused(report, name: "subscript", owner: "A", kind: .subscript, labels: ["captured"])
            }
            for owner in ["B", "Other"] {
                try requireUnused(report, name: "captured", owner: owner)
                try requireUnused(report, name: "subscript", owner: owner, kind: .subscript, labels: ["captured"])
            }
            for owner in ["A", "B", "Other"] {
                try requireUnused(report, name: "neverCalled", owner: owner)
            }
            try requireUnused(report, name: "inside", owner: "Other")
            try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: ["inside"])
            try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: ["after"])
        }
    }

    @Test
    func captureInitializersResolveNominalTypesBeforeInstallingTypeNamedCaptures() async throws {
        try await withProject([
            "main.swift": """
            struct Token {
                subscript(index index: Int) -> Int { index }
            }
            extension Token {
                init(seed: Int) { _ = seed }
                init(unused: Int) { _ = unused }
            }
            struct Other {
                subscript(index index: Int) -> Int { index }
            }
            extension Other { init(seed: Int) { _ = seed } }
            let operation = { [Token = {}, made = Token(seed: 1)] in
                Token()
                _ = made[index: 1]
            }
            operation()
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "init", owner: "Token", kind: .initializer, labels: ["seed"])
            try requireUsed(report, declarations: declarations, name: "subscript", owner: "Token", kind: .subscript, labels: ["index"])
            try requireUnused(report, name: "init", owner: "Token", kind: .initializer, labels: ["unused"])
            try requireUnused(report, name: "init", owner: "Other", kind: .initializer, labels: ["seed"])
            try requireUnused(report, name: "subscript", owner: "Other", kind: .subscript, labels: ["index"])
        }
    }

    @Test(arguments: ["function", "initializer", "subscript"])
    func parameterDefaultExpressionsResolveOuterBindingsBeforeInstallingParameters(_ kind: String) async throws {
        let declaration: String
        let call: String
        switch kind {
        case "function":
            declaration = """
                func exercise(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) {
                    _ = maker.init(body: 1)
                    _ = value
                }
                """
            call = "exercise()"
        case "initializer":
            declaration = """
                struct Owner {}
                extension Owner {
                    init(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) {
                        _ = maker.init(body: 1)
                        _ = value
                    }
                }
                """
            call = "_ = Owner(Wrong.self)"
        default:
            declaration = """
                struct Owner {
                    subscript(_ maker: Wrong.Type = Wrong.self, _ value: Live = maker.init(seed: 1)) -> Int {
                        _ = maker.init(body: 1)
                        _ = value
                        return 0
                    }
                }
                """
            call = "_ = Owner()[Wrong.self]"
        }
        try await withProject([
            "main.swift": """
            struct Live {}
            extension Live {
                init(seed: Int) { _ = seed }
                init(body: Int) { _ = body }
            }
            struct Wrong {}
            extension Wrong {
                init(seed: Int) { _ = seed }
                init(body: Int) { _ = body }
            }
            let maker: Live.Type = Live.self
            \(declaration)
            \(call)
            """
        ]) { report, declarations, _ in
            try requireUsed(report, declarations: declarations, name: "init", owner: "Live", kind: .initializer, labels: ["seed"])
            try requireUsed(report, declarations: declarations, name: "init", owner: "Wrong", kind: .initializer, labels: ["body"])
            try requireUnused(report, name: "init", owner: "Live", kind: .initializer, labels: ["body"])
            try requireUnused(report, name: "init", owner: "Wrong", kind: .initializer, labels: ["seed"])
        }
    }
}
