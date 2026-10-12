import Foundation
import SwiftParser
import Testing
@testable import unused

struct ReferenceGraphServiceTests {
    private func graph(
        _ files: [String: String], name: String = "target", type: DeclarationType = .function,
        file: String = "Main.swift", line: Int = 1, parentType: String? = nil, includeTests: Bool = false
    ) async throws -> ReferenceGraphResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (path, source) in files {
            let url = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
        let target = ReportItem(id: 1, name: name, type: type, file: directory.appendingPathComponent(file).path,
                                line: line, exclusionReason: .none, parentType: parentType)
        return await ReferenceGraphService().buildGraph(for: target, in: directory.path, includeTests: includeTests)
    }

    private func graphFromDeclaration(
        _ source: String, currentSource: String? = nil, select: (Declaration) -> Bool
    ) async throws -> ReferenceGraphResult {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let file = directory.appendingPathComponent("CanonicalGraph.swift")
        let sourceFile = Parser.parse(source: source)
        let declarations = DeclarationVisitor(filePath: file.path, protocolRequirements: [:], sourceFile: sourceFile)
        declarations.walk(sourceFile)
        let selected = declarations.declarations.first(where: select)
        let declaration = try #require(selected)
        let report = ReportItem(id: 1, declaration: declaration)
        let service = ReferenceGraphService(
            discoverFiles: { _, _ in SwiftFileDiscoveryResult(files: [file], excludedTestFileCount: 0) },
            readSource: { _ in currentSource ?? source }
        )
        return await service.buildGraph(for: report, in: directory.path)
    }

    @Test func canonicalNestedDeclarationReportsFindTheirGraphRootsAndReferences() async throws {
        let result = try await graphFromDeclaration("""
        struct Outer {
            struct Inner {
                func target() { helper() }
                func helper() {}
                func caller() { self.target() }
            }
        }
        """, select: { $0.name == "target" })
        #expect(result.targetFound)
        #expect(result.root?.parentType == "Outer.Inner")
        #expect(result.inbound.map(\.displayName) == ["Outer.Inner.caller()"])
        #expect(result.outbound.map(\.displayName) == ["Outer.Inner.helper()"])
    }

    @Test func canonicalNestedTypeReportsFindTheirOwnGraphRoots() async throws {
        let result = try await graphFromDeclaration("""
        struct Outer { struct Inner {} }
        struct Other { struct Inner {} }
        """, select: { $0.name == "Inner" && $0.parentType == "Outer" })
        #expect(result.targetFound)
        #expect(result.root?.name == "Inner")
        #expect(result.root?.parentType == "Outer")
        #expect(result.root?.kind == "struct")
    }

    @Test func canonicalQualifiedExtensionReportsMatchTheirSourceOwner() async throws {
        let result = try await graphFromDeclaration("""
        struct `Outer` { struct `Inner`<T> { func helper() {} } }
        extension `Outer`.`Inner`<Int> {
            func target() { self.helper() }
        }
        """, select: { $0.name == "target" })
        #expect(result.targetFound)
        #expect(result.root?.parentType == "Outer.Inner")
        #expect(result.outbound.map(\.name) == ["helper"])
        #expect(result.edges.filter { $0.source == result.root }.allSatisfy { !$0.isAmbiguous })
    }

    @Test func nestedReceiverPathsWorkAcrossFilesWithoutMatchingEqualLeafOwners() async throws {
        let result = try await graph([
            "Main.swift": "struct Outer { struct Inner { static func target() {} } }\nstruct Other { struct Inner { static func target() {} } }",
            "Caller.swift": "func caller(_ value: Outer.Inner) { value.target(); Outer.Inner.target(); Other.Inner.target() }"
        ], parentType: "Outer.Inner")
        #expect(result.targetFound)
        let incoming = result.edges.filter { $0.target == result.root }
        #expect(incoming.count == 2)
        #expect(incoming.allSatisfy { $0.usage.receiverType == "Outer.Inner" && !$0.isAmbiguous })
    }

    @Test func nestedConstructorReportsIncludeDirectAndExtensionInitializers() async throws {
        let direct = try await graphFromDeclaration("""
        struct Outer { struct Inner { init() {} } }
        func caller() { _ = Outer.Inner() }
        """, select: { $0.name == "init" })
        #expect(direct.targetFound)
        #expect(direct.root?.parentType == "Outer.Inner")
        #expect(direct.inbound.map(\.name) == ["caller"])
        let extended = try await graphFromDeclaration("""
        struct Outer { struct Inner {} }
        extension Outer.Inner { init() {} }
        func caller() { _ = Outer.Inner() }
        """, select: { $0.name == "init" })
        #expect(extended.targetFound)
        #expect(extended.inbound.map(\.name) == ["caller"])
    }

    @Test func canonicalIdentityDisambiguatesSameNameOverloadsOnTheSameLine() async throws {
        let result = try await graphFromDeclaration("""
        func target(_ value: Int) { integerDependency() }; func target(_ value: String) { stringDependency() }
        func integerDependency() {}
        func stringDependency() {}
        """, select: { $0.name == "target" && $0.identity?.signature.parameterTypes == ["String"] })
        #expect(result.targetFound)
        #expect(result.root?.line == 1)
        #expect((result.root?.column ?? 0) > 1)
        #expect(result.outbound.map(\.name) == ["stringDependency"])
        #expect(!result.warnings.contains { $0.contains("cannot distinguish") })
    }

    @Test func staleIdentityOffsetsDoNotFallBackToSameNameReportLocations() async throws {
        let result = try await graphFromDeclaration(
            "func target() {}", currentSource: " func target() {}", select: { $0.name == "target" }
        )
        #expect(!result.targetFound)
        #expect(result.warnings.contains { $0.contains("refresh the IDs") })
    }

    @Test func changedSignaturesAtTheSameOffsetDoNotSelectReorderedOverloads() async throws {
        let result = try await graphFromDeclaration(
            "func target(_ value: Int) {}; func target(_ value: String) {}",
            currentSource: "func target(_ value: String) {}; func target(_ value: Int) {}",
            select: { $0.name == "target" && $0.identity?.signature.parameterTypes == ["Int"] }
        )
        #expect(!result.targetFound)
        #expect(result.warnings.contains { $0.contains("refresh the IDs") })
    }

    @Test func canonicalMultiBindingReportsUseBindingOffsetsAndOriginalReportLines() async throws {
        let result = try await graphFromDeclaration("""
        let first = 1,
            target = helper()
        func helper() -> Int { 0 }
        """, select: { $0.name == "target" })
        #expect(result.targetFound)
        #expect(result.root?.line == 1)
        #expect(result.outbound.map(\.name) == ["helper"])
    }

    @Test func findsBothDirectionsAndActualUsageSites() async throws {
        let result = try await graph([
            "Main.swift": "func target() { helper() }",
            "Other.swift": "func helper() {}\nfunc caller() { target(); target() }"
        ])
        #expect(result.targetFound)
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.outbound.map(\.name) == ["helper"])
        let incoming = result.edges.filter { $0.target == result.root }
        #expect(incoming.count == 2)
        #expect(incoming.allSatisfy { $0.usage.line == 2 && $0.usage.kind == .call && !$0.isAmbiguous })
        #expect(Set(incoming.map { $0.usage.column }).count == 2)
        #expect(result.scannedFileCount == 2)
    }

    @Test func typedAndStaticReceiversDoNotLinkUnrelatedSameNameMethods() async throws {
        let result = try await graph([
            "Main.swift": "struct A { static func target() {} }\nstruct B { static func target() {} }",
            "Other.swift": "func caller(_ a: A?, _ b: B) { a?.target(); b.target(); A.target() }"
        ], parentType: "A")
        #expect(result.inbound.map(\.name) == ["caller"])
        let sites = result.edges.filter { $0.target == result.root }
        #expect(sites.count == 2)
        #expect(sites.allSatisfy { $0.usage.receiverType == "A" && !$0.isAmbiguous })
    }

    @Test func selfAndBareMembersResolveWithinTheCurrentType() async throws {
        let result = try await graph([
            "Main.swift": "struct A { func target() {}\nfunc caller() { self.target(); target() } }\nstruct B { func target() {} }"
        ], parentType: "A")
        #expect(result.edges.filter { $0.target == result.root }.count == 2)
        #expect(result.inbound.map(\.displayName) == ["A.caller()"])
    }

    @Test func unknownReceiversAreMarkedAsPossibleNotConfirmed() async throws {
        let result = try await graph([
            "Main.swift": "struct A { func target() {} }\nfunc caller(_ unknown: Any) { unknown.target() }"
        ], parentType: "A")
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.edges.filter { $0.target == result.root }.allSatisfy { edge in edge.isAmbiguous })
    }

    @Test func localParametersAndVariablesDoNotReferenceProjectNames() async throws {
        let result = try await graph([
            "Main.swift": "func target() {}\nfunc caller(target: () -> Void) { target() }\nfunc another() { let target = {}; target() }"
        ])
        #expect(result.inbound.isEmpty)
    }

    @Test func overloadLabelsNarrowCandidatesWithoutGuessingArgumentTypes() async throws {
        let result = try await graph([
            "Main.swift": "func target(id: Int) {}\nfunc target(name: String) {}\nfunc caller() { target(id: 1) }"
        ])
        let incoming = result.edges.filter { $0.target == result.root }
        #expect(incoming.count == 1)
        #expect(incoming.allSatisfy { !$0.isAmbiguous })
        #expect(result.edges.filter { $0.target.name == "target" }.count == 1)
        #expect(result.root?.signature == "target(id:)")
    }

    @Test func defaultArgumentsDoNotDiscardOtherCompatibleOverloads() async throws {
        let result = try await graph([
            "Main.swift": "func target(_ value: Int) {}\nfunc target(_ value: String, mode: Int = 0) {}\nfunc caller() { target(\"text\") }"
        ], line: 2)
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.edges.filter { $0.usage.name == "target" }.count == 2)
        #expect(result.edges.filter { $0.usage.name == "target" }.allSatisfy { edge in edge.isAmbiguous })
    }

    @Test func variadicArgumentsResolveWithoutSpuriousUncertainty() async throws {
        let result = try await graph([
            "Main.swift": "func target(_ values: Int...) {}\nfunc caller() { target(1, 2, 3) }"
        ])
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.edges.filter { $0.target == result.root }.allSatisfy { !$0.isAmbiguous })
    }

    @Test func blockLocalFunctionsDoNotShadowCallsAfterTheBlock() async throws {
        let result = try await graph([
            "Main.swift": "func target() {}\nfunc caller() {\nif Bool.random() { func target() {}; target() }\ntarget()\n}"
        ])
        let incoming = result.edges.filter { $0.target == result.root }
        #expect(incoming.count == 1)
        #expect(incoming.first?.usage.line == 4)
        #expect(incoming.first?.isAmbiguous == false)
    }

    @Test func closureLocalFunctionsDoNotLeakAndNestedOwnershipIsIsolated() async throws {
        let result = try await graph([
            "Main.swift": "func target() {}\nfunc caller() {\nlet work = { func target() {}; target() }\nfunc nested() { target() }\ntarget()\n}"
        ])
        #expect(Set(result.inbound.map(\.name)) == ["nested", "caller"])
        #expect(Set(result.edges.filter { $0.target == result.root }.map { $0.usage.line }) == [4, 5])
    }

    @Test func defaultParameterExpressionReferencesTheOuterDeclaration() async throws {
        let result = try await graph([
            "Main.swift": "func target() {}\nfunc caller(target: () -> Void = target) { target() }"
        ])
        #expect(result.inbound.map(\.name) == ["caller"])
        let incoming = result.edges.filter { $0.target == result.root }
        #expect(incoming.count == 1)
        #expect(incoming.first?.usage.kind == .reference)
    }

    @Test func recursiveCallsArePreservedInsteadOfClaimingNoReferences() async throws {
        let result = try await graph(["Main.swift": "func target() { target() }"])
        #expect(result.inbound == [result.root].compactMap { $0 })
        #expect(result.outbound == result.inbound)
        #expect(result.edges.count == 1)
    }

    @Test func storedPropertiesWithoutInitializersHaveReadsAndWrites() async throws {
        let result = try await graph([
            "Main.swift": "struct A { var target: Int\nfunc caller() { self.target = 1; print(self.target) } }"
        ], type: .variable, parentType: "A")
        #expect(result.targetFound)
        #expect(result.root?.kind == "variable")
        #expect(Set(result.edges.filter { $0.target == result.root }.map { $0.usage.kind }) == [.write, .read])
    }

    @Test func allMultiBindingPropertiesAreIndexedIndependently() async throws {
        let result = try await graph([
            "Main.swift": "let first = 1, target = helper()\nfunc helper() {}\nfunc caller() { print(target) }"
        ], type: .variable)
        #expect(result.targetFound)
        #expect(result.outbound.map(\.name) == ["helper"])
        #expect(result.inbound.map(\.name) == ["caller"])
    }

    @Test func typesAliasesEnumCasesAndFileScopeAreIncluded() async throws {
        let result = try await graph([
            "Main.swift": "struct target {}\ntypealias Alias = target\nlet value = target()\nprint(target.self)"
        ], type: .class)
        #expect(result.root?.kind == "struct")
        #expect(Set(result.inbound.map(\.name)) == ["Alias", "value", "<file scope>"])
        let enumResult = try await graph([
            "Main.swift": "enum Kind { case target }\nfunc caller() { print(Kind.target) }"
        ], type: .enumCase, parentType: "Kind")
        #expect(enumResult.targetFound)
        #expect(enumResult.inbound.map(\.name) == ["caller"])
    }

    @Test func constructorReferencesIncludeOnlyVisibleTypeInitializers() async throws {
        let result = try await graph([
            "Main.swift": "struct Token { init() {} }\nfunc hidden() { struct Token { init() {} } }\nfunc caller() { _ = Token() }"
        ], name: "init", parentType: "Token")
        #expect(result.inbound.map(\.name) == ["caller"])
        let initializerEdges = result.edges.filter { $0.source.name == "caller" && $0.target.name == "init" }
        #expect(initializerEdges.count == 1)
        #expect(initializerEdges.first?.target.line == 1)
        #expect(initializerEdges.first?.isAmbiguous == false)
    }

    @Test func constructorsFindInitializersDeclaredInExtensionsAcrossFiles() async throws {
        let result = try await graph([
            "Main.swift": "struct Token {}\nfunc caller() { _ = Token() }",
            "Extension.swift": "extension Token { init() {} }"
        ], name: "init", file: "Extension.swift", parentType: "Token")
        #expect(result.targetFound)
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.edges.filter { $0.target == result.root }.count == 1)
    }

    @Test func typeMemberOperatorsArePossibleDependencies() async throws {
        let result = try await graph([
            "Main.swift": "struct Value { static func + (_ lhs: Self, _ rhs: Self) -> Self { lhs } }\nfunc caller(_ a: Value, _ b: Value) { _ = a + b }"
        ], name: "+", parentType: "Value")
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.edges.filter { $0.target == result.root }.allSatisfy { edge in edge.isAmbiguous })
    }

    @Test func staleOrAmbiguousReportLocationsCannotProduceRemovalAssessments() async throws {
        let stale = try await graph(["Main.swift": "\nfunc target() {}"])
        #expect(!stale.targetFound)
        #expect(stale.warnings.contains { $0.contains("refresh the IDs") })
        let ambiguous = try await graph(["Main.swift": "func target(_ a: Int) {}; func target(_ a: String) {}"])
        #expect(!ambiguous.targetFound)
        #expect(ambiguous.warnings.contains { $0.contains("cannot distinguish") })
    }

    @Test func testScopeIsExplicitAndUnresolvedCallsRemainVisible() async throws {
        let files = ["Main.swift": "func target() { print(1) }", "Tests/CallerTests.swift": "func testCaller() { target() }"]
        let excluded = try await graph(files)
        #expect(excluded.inbound.isEmpty)
        #expect(!excluded.includesTests)
        #expect(excluded.warnings.contains { $0.contains("test files excluded") })
        #expect(excluded.unresolved.map(\.name) == ["print"])
        let included = try await graph(files, includeTests: true)
        #expect(included.inbound.map(\.name) == ["testCaller"])
        #expect(included.includesTests)
        #expect(included.scannedFileCount == 2)
    }

    @Test func syntaxErrorsAndMissingDeclarationsAreReported() async throws {
        let result = try await graph(["Main.swift": "func target() { helper( }", "Other.swift": "func helper() {}"])
        #expect(result.warnings.contains { $0.contains("Syntax errors") })
        let missing = try await graph(["Other.swift": "func another() {}"])
        #expect(!missing.targetFound)
    }

    @Test func filesystemDependenciesAreInjectableAndReadFailuresAreReported() async throws {
        let directory = FileManager.default.temporaryDirectory
        let file = directory.appendingPathComponent("unreadable.swift")
        let service = ReferenceGraphService(
            discoverFiles: { _, _ in SwiftFileDiscoveryResult(files: [file], excludedTestFileCount: 0) },
            readSource: { _ in throw CocoaError(.fileReadUnknown) }
        )
        let target = ReportItem(id: 1, name: "target", type: .function, file: file.path, line: 1, exclusionReason: .none, parentType: nil)
        let result = await service.buildGraph(for: target, in: directory.path)
        #expect(!result.targetFound)
        #expect(result.scannedFileCount == 0)
        #expect(result.warnings.contains { $0.contains("Could not read") })
    }

    @Test func invalidDirectoryAndUnsupportedFindingHaveActionableWarnings() async throws {
        let target = ReportItem(id: 1, name: "target", type: .function, file: "Main.swift", line: 1, exclusionReason: .none, parentType: nil)
        let invalid = await ReferenceGraphService().buildGraph(for: target, in: "/nonexistent/\(UUID().uuidString)")
        #expect(!invalid.targetFound)
        #expect(invalid.warnings.contains { $0.contains("Directory does not exist") })
        let parameter = try await graph(["Main.swift": "func method(target: Int) {}"], type: .parameter)
        #expect(!parameter.targetFound)
        #expect(parameter.warnings.contains { $0.contains("enclosing declaration") })
    }

    @Test func canonicalRelativeAndSymlinkPathsResolveToTheSameDeclaration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: directory)
        }
        try "func target() {}\nfunc caller() { target() }".write(to: directory.appendingPathComponent("Main.swift"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        let target = ReportItem(id: 1, name: "target", type: .function, file: "Main.swift", line: 1, exclusionReason: .none, parentType: nil)
        let result = await ReferenceGraphService().buildGraph(for: target, in: alias.path)
        #expect(result.targetFound)
        #expect(result.inbound.map(\.name) == ["caller"])
        #expect(result.root?.file == directory.resolvingSymlinksInPath().appendingPathComponent("Main.swift").path)
    }

    @Test func outputOrderingIsDeterministicAcrossConcurrentRuns() async throws {
        let files = ["Main.swift": "func target() { b(); a() }", "B.swift": "func b() {}", "A.swift": "func a() {}"]
        let result = try await graph(files)
        #expect(result.outbound.map(\.name) == ["a", "b"])
        #expect(result.edges.filter { $0.source.name == "target" }.map { $0.target.name } == ["a", "b"])
    }
}
