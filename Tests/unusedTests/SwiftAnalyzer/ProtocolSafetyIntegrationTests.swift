import Foundation
import SwiftParser
import Testing

@testable import unused

struct ProtocolSafetyIntegrationTests {
    private static let swiftInterface = """
        public protocol Equatable {
            static func == (_ lhs: Self, _ rhs: Self) -> Bool
        }
        public protocol Hashable: Swift.Equatable {
            func hash(into hasher: inout Swift.Hasher)
        }
        public protocol Sendable {}
        public protocol CustomStringConvertible {
            var description: Swift.String { get }
        }
        """

    private func withProject(
        _ sources: [String: String],
        swiftInterface: String = Self.swiftInterface,
        moduleName: String? = nil,
        verify: (Report, URL) throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtocolSafety-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let files = try sources.sorted(by: { $0.key < $1.key }).map { entry in
            let file = directory.appendingPathComponent(entry.key)
            try entry.value.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { module in
            module == "Swift" ? swiftInterface : nil
        })
        let analyzer = SwiftAnalyzer(
            directory: directory.path,
            swiftInterfaceClient: client,
            moduleName: moduleName,
            progressTrackerFactory: { total, prefix in
                ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
            }
        )
        let report = await analyzer.analyzeFiles(files)
        try verify(report, directory)
    }

    private func matches(
        _ item: ReportItem,
        name: String,
        owner: String,
        kind: MemberKind,
        labels: [String]? = nil
    ) -> Bool {
        guard item.name == name, let identity = item.identity,
            identity.ownerName == owner, identity.signature.kind == kind
        else { return false }
        guard let labels else { return true }
        return identity.signature.parameterLabels == labels
    }

    @discardableResult
    private func requireWitness(
        _ report: Report,
        name: String,
        owner: String,
        kind: MemberKind = .function,
        labels: [String]? = nil,
        reason: ExclusionReason = .protocolImplementation
    ) throws -> ReportItem {
        let item = try #require(
            report.excluded.protocolImplementations.first {
                matches($0, name: name, owner: owner, kind: kind, labels: labels)
            })
        #expect(item.exclusionReason == reason)
        #expect(
            !report.unused.contains {
                matches($0, name: name, owner: owner, kind: kind, labels: labels)
            })
        return item
    }

    @discardableResult
    private func requireUnused(
        _ report: Report,
        name: String,
        owner: String,
        kind: MemberKind = .function,
        labels: [String]? = nil
    ) throws -> ReportItem {
        let item = try #require(
            report.unused.first {
                matches($0, name: name, owner: owner, kind: kind, labels: labels)
            })
        #expect(item.exclusionReason == .none)
        #expect(
            !report.excluded.protocolImplementations.contains {
                matches($0, name: name, owner: owner, kind: kind, labels: labels)
            })
        return item
    }

    @Test
    func crossFileConformanceProtectsWitnessDeclaredInAnotherFile() async throws {
        try await withProject([
            "Requirements.swift": """
            protocol Working { func work(_ value: Int) }
            """,
            "Worker.swift": """
            struct Worker {
                func work(_ value: Int) { print(value) }
                func splitHelper() {}
            }
            """,
            "Worker+Working.swift": """
            extension Worker: Working {}
            """,
            "main.swift": """
            _ = Worker()
            """,
        ]) { report, _ in
            let witness = try requireWitness(report, name: "work", owner: "Worker", labels: ["_"])
            #expect(witness.identity?.file.hasSuffix("/Worker.swift") == true)
            try requireUnused(report, name: "splitHelper", owner: "Worker")
        }
    }

    @Test
    func localTypeWitnessSurvivesWhileSameNamedNestedHelperRemainsUnused() async throws {
        try await withProject([
            "main.swift": """
            protocol P { func work() }
            func exercise() {
                struct Local: P {
                    func work() {
                        func work() {}
                    }
                    func localHelper() {}
                }
                _ = Local()
            }
            exercise()
            """
        ]) { report, directory in
            let file = directory.appendingPathComponent("main.swift")
            let source = try String(contentsOf: file, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)
            let protocols = ProtocolVisitor()
            protocols.walk(sourceFile)
            #expect(protocols.result.typeInheritance["Local"] == ["P"])

            let declarations = DeclarationVisitor(
                filePath: file.path, protocolRequirements: [:], sourceFile: sourceFile
            )
            declarations.walk(sourceFile)
            let member = try #require(
                declarations.declarations.first {
                    $0.name == "work" && $0.identity?.ownerName == "Local"
                        && $0.identity?.isTypeMember == true
                }?.identity)
            let nestedHelper = try #require(
                declarations.declarations.first {
                    $0.name == "work" && $0.identity?.ownerName == "Local"
                        && $0.identity?.isTypeMember == false
                }?.identity)
            #expect(!member.lexicalScope.isEmpty)
            #expect(nestedHelper.lexicalScope.count > member.lexicalScope.count)

            let witness = try #require(
                report.excluded.protocolImplementations.first {
                    $0.identity == member
                })
            #expect(witness.exclusionReason == .protocolImplementation)
            #expect(!report.unused.contains { $0.identity == member })
            let unusedNestedHelper = try #require(
                report.unused.first {
                    $0.identity == nestedHelper
                })
            #expect(unusedNestedHelper.exclusionReason == .none)
            #expect(
                !report.excluded.protocolImplementations.contains { $0.identity == nestedHelper })
            try requireUnused(report, name: "localHelper", owner: "Local")
        }
    }

    @Test
    func subclassConformanceProtectsSuperclassProviderWithoutCallingIt() async throws {
        try await withProject([
            "main.swift": """
            protocol Working { func work(_ value: Int) }
            class Base {
                func work(_ value: Int) { print(value) }
                func superclassHelper() {}
            }
            final class Worker: Base, Working {}
            _ = Worker()
            """
        ]) { report, _ in
            try requireWitness(report, name: "work", owner: "Base", labels: ["_"])
            try requireUnused(report, name: "superclassHelper", owner: "Base")
            #expect(!report.warnings.contains { $0.contains("Base") })
        }
    }

    @Test
    func protocolDefaultInSeparateFileIsRetainedWithoutExplicitMemberCalls() async throws {
        try await withProject([
            "Defaults.swift": """
            extension Working {
                func work(_ value: Int) { print(value) }
                func defaultHelper() {}
            }
            """,
            "Requirements.swift": """
            protocol Working { func work(_ value: Int) }
            """,
            "main.swift": """
            struct Worker: Working {
                func concreteHelper() {}
            }
            _ = Worker()
            """,
        ]) { report, _ in
            try requireWitness(report, name: "work", owner: "Working", labels: ["_"])
            try requireUnused(report, name: "defaultHelper", owner: "Working")
            try requireUnused(report, name: "concreteHelper", owner: "Worker")
        }
    }

    @Test
    func conditionalConformancePreservesPlausibleGenericProvider() async throws {
        try await withProject([
            "main.swift": """
            protocol Working { func work(_ value: Int) }
            struct Box<T> {
                func work(_ value: Int) { print(value) }
                func conditionalHelper() {}
            }
            #if USE_EQUATABLE
            extension Box: Working where T: Equatable {}
            #else
            extension Box: Working where T: Hashable {}
            #endif
            _ = Box<Int>()
            """
        ]) { report, _ in
            try requireWitness(report, name: "work", owner: "Box", labels: ["_"])
            try requireUnused(report, name: "conditionalHelper", owner: "Box")
        }
    }

    @Test
    func associatedTypesProtectNestedTypealiasAndConcreteTypeWitnesses() async throws {
        try await withProject([
            "main.swift": """
            protocol Container { associatedtype Element }
            protocol Tree { associatedtype Node }
            enum Namespace {
                struct Bag: Container {
                    typealias Element = Int
                    typealias UnusedAlias = String
                    func containerHelper() {}
                }
                struct Root: Tree { struct Node {} }
            }
            struct OtherBag { typealias Element = Int }
            _ = Namespace.Bag()
            _ = Namespace.Root()
            _ = OtherBag()
            """
        ]) { report, _ in
            try requireWitness(
                report, name: "Element", owner: "Namespace.Bag", kind: .typealiasDeclaration
            )
            try requireWitness(report, name: "Node", owner: "Namespace.Root", kind: .type)
            try requireUnused(
                report, name: "UnusedAlias", owner: "Namespace.Bag", kind: .typealiasDeclaration
            )
            try requireUnused(
                report, name: "Element", owner: "OtherBag", kind: .typealiasDeclaration
            )
            try requireUnused(report, name: "containerHelper", owner: "Namespace.Bag")
        }
    }

    @Test
    func escapedQualifiedProtocolAndRequirementNamesResolve() async throws {
        try await withProject([
            "main.swift": """
            enum Namespace {
                protocol `default` { func `repeat`(_ value: Int) }
            }
            struct Worker: Namespace.`default` {
                func `repeat`(_ value: Int) { print(value) }
                func escapedHelper() {}
            }
            _ = Worker()
            """
        ]) { report, _ in
            try requireWitness(report, name: "repeat", owner: "Worker", labels: ["_"])
            try requireUnused(report, name: "escapedHelper", owner: "Worker")
            #expect(!report.warnings.contains { $0.contains("Namespace.default") })
        }
    }

    @Test
    func chainedAliasAndCompositionConformanceResolveRelativeToNamespace() async throws {
        try await withProject([
            "main.swift": """
            protocol Working { func work(_ value: Int) }
            protocol Named { var title: String { get } }
            enum Namespace {
                typealias Pair = Working & Named
                typealias Alias = Pair
                struct Worker: Alias {
                    var title: String { "worker" }
                    func work(_ value: Int) { print(value) }
                    func compositionHelper() {}
                }
            }
            _ = Namespace.Worker()
            """
        ]) { report, _ in
            try requireWitness(report, name: "work", owner: "Namespace.Worker", labels: ["_"])
            try requireWitness(report, name: "title", owner: "Namespace.Worker", kind: .property)
            try requireUnused(report, name: "compositionHelper", owner: "Namespace.Worker")
        }
    }

    @Test
    func qualifiedNestedTypeReferenceDoesNotUseSameLeafInOtherNamespace() async throws {
        try await withProject([
            "main.swift": """
            enum First { struct Node {} }
            enum Second { struct Node {} }
            _ = First.Node()
            """
        ]) { report, _ in
            #expect(
                !report.unused.contains {
                    matches($0, name: "Node", owner: "First", kind: .type)
                })
            try requireUnused(report, name: "Node", owner: "Second", kind: .type)
        }
    }

    @Test
    func differentArgumentLabelOverloadRemainsUnused() async throws {
        try await withProject([
            "main.swift": """
            protocol Working { func work(_ value: Int) }
            struct Worker: Working {
                func work(_ value: Int) { print(value) }
                func work(other value: Int) { print(value) }
                func overloadHelper() {}
            }
            struct Other {
                func work(_ value: Int) { print(value) }
            }
            _ = Worker()
            _ = Other()
            """
        ]) { report, _ in
            let witness = try requireWitness(report, name: "work", owner: "Worker", labels: ["_"])
            let overload = try requireUnused(
                report, name: "work", owner: "Worker", labels: ["other"])
            #expect(witness.identity != overload.identity)
            try requireUnused(report, name: "work", owner: "Other", labels: ["_"])
            try requireUnused(report, name: "overloadHelper", owner: "Worker")
        }
    }

    @Test
    func concreteReturnTypeOverloadRemainsUnused() async throws {
        try await withProject([
            "main.swift": """
            protocol Producing {
                func value() -> Int
                func action()
            }
            struct Worker: Producing {
                func value() -> Int { 1 }
                func value() -> String { "unused" }
                func action() {}
                func action() -> String { "unused" }
                func resultHelper() {}
            }
            _ = Worker()
            """
        ]) { report, _ in
            let witness = try #require(
                report.excluded.protocolImplementations.first {
                    matches($0, name: "value", owner: "Worker", kind: .function)
                        && $0.identity?.signature.resultType == "Int"
                })
            let overload = try #require(
                report.unused.first {
                    matches($0, name: "value", owner: "Worker", kind: .function)
                        && $0.identity?.signature.resultType == "String"
                })
            #expect(witness.exclusionReason == .protocolImplementation)
            #expect(overload.exclusionReason == .none)
            #expect(witness.identity != overload.identity)
            #expect(!report.unused.contains { $0.identity == witness.identity })
            #expect(
                !report.excluded.protocolImplementations.contains {
                    $0.identity == overload.identity
                })
            let voidWitness = try #require(
                report.excluded.protocolImplementations.first {
                    matches($0, name: "action", owner: "Worker", kind: .function)
                        && $0.identity?.signature.resultType == nil
                })
            let returningOverload = try #require(
                report.unused.first {
                    matches($0, name: "action", owner: "Worker", kind: .function)
                        && $0.identity?.signature.resultType == "String"
                })
            #expect(voidWitness.exclusionReason == .protocolImplementation)
            #expect(returningOverload.exclusionReason == .none)
            #expect(!report.unused.contains { $0.identity == voidWitness.identity })
            #expect(
                !report.excluded.protocolImplementations.contains {
                    $0.identity == returningOverload.identity
                })
            try requireUnused(report, name: "resultHelper", owner: "Worker")
        }
    }

    @Test
    func injectedHashableMetadataProtectsTransitiveEquatableWitness() async throws {
        try await withProject([
            "main.swift": """
            struct Token: Hashable {
                static func == (_ lhs: Token, _ rhs: Token) -> Bool { true }
                func hash(into hasher: inout Hasher) { hasher.combine(0) }
                func hashableHelper() {}
            }
            _ = Token()
            """
        ]) { report, _ in
            let equality = try requireWitness(
                report, name: "==", owner: "Token", labels: ["_", "_"])
            #expect(equality.identity?.signature.isStatic == true)
            try requireWitness(report, name: "hash", owner: "Token", labels: ["into"])
            try requireUnused(report, name: "hashableHelper", owner: "Token")
        }
    }

    @Test
    func knownEmptyExternalProtocolDoesNotSuppressUnusedHelper() async throws {
        try await withProject([
            "main.swift": """
            struct Marker: Sendable {
                func emptyProtocolHelper() {}
            }
            _ = Marker()
            """
        ]) { report, _ in
            try requireUnused(report, name: "emptyProtocolHelper", owner: "Marker")
            #expect(!report.warnings.contains { $0.contains("Sendable") })
        }
    }

    @Test
    func unavailableFoundationProtocolRetainsCandidateAndNamesWarning() async throws {
        try await withProject([
            "main.swift": """
            import Foundation
            final class Copier: NSCopying {
                func copy(with zone: NSZone? = nil) -> Any { self }
            }
            struct Control {
                func unknownProtocolControl() {}
            }
            _ = Copier()
            _ = Control()
            """
        ]) { report, _ in
            try requireWitness(
                report, name: "copy", owner: "Copier", labels: ["with"], reason: .unresolvedProtocol
            )
            #expect(report.warnings.contains { $0.contains("NSCopying") })
            try requireUnused(report, name: "unknownProtocolControl", owner: "Control")
        }
    }

    @Test
    func partialExternalInheritanceRequiresKnownMembersAndRetainsUnknownCandidates() async throws {
        let partialInterface = Self.swiftInterface.replacing(
            "public protocol CustomStringConvertible {",
            with: "public protocol CustomStringConvertible: MissingParent {"
        )
        try await withProject(
            [
                "main.swift": """
                protocol Refined: CustomStringConvertible { func known() }
                struct Partial: Refined {
                    var description: String { "partial" }
                    func known() {}
                    func possibleInheritedRequirement() {}
                }
                _ = Partial()
                """
            ],
            swiftInterface: partialInterface
        ) { report, _ in
            try requireWitness(report, name: "known", owner: "Partial")
            try requireWitness(report, name: "description", owner: "Partial", kind: .property)
            try requireWitness(
                report, name: "possibleInheritedRequirement", owner: "Partial",
                reason: .unresolvedProtocol
            )
            #expect(report.warnings.contains { $0.contains("MissingParent") })
        }
    }

    @Test
    func reportServiceRoundtripsWarningsAndExplicitModuleSignatureIdentity() async throws {
        try await withProject(
            [
                "main.swift": """
                import Foundation
                protocol Recordable {
                    static func record<T>(_ value: T, named name: String) async throws -> String
                }
                struct Recorder: Recordable {
                    static func record<T>(_ value: T, named name: String) async throws -> String {
                        _ = value
                        return name
                    }
                    func roundtripHelper(_ value: Int) -> String { String(value) }
                }
                final class Copier: NSCopying {
                    func copy(with zone: NSZone? = nil) -> Any { self }
                }
                _ = Recorder()
                _ = Copier()
                """
            ],
            moduleName: "SafetyFixtures"
        ) { report, directory in
            let witness = try requireWitness(
                report, name: "record", owner: "Recorder", labels: ["_", "named"]
            )
            let unused = try requireUnused(
                report, name: "roundtripHelper", owner: "Recorder", labels: ["_"]
            )
            try requireWitness(
                report, name: "copy", owner: "Copier", labels: ["with"], reason: .unresolvedProtocol
            )
            let identity = try #require(witness.identity)
            let expectedSignature = MemberSignature(
                kind: .function, name: "record", isStatic: true,
                parameterLabels: ["_", "named"], parameterTypes: ["T", "String"],
                resultType: "String",
                genericParameters: ["T"], isAsync: true, isThrowing: true
            )
            #expect(identity.moduleName == "SafetyFixtures")
            #expect(identity.enclosingTypePath == ["Recorder"])
            #expect(identity.lexicalScope.isEmpty)
            #expect(identity.signature == expectedSignature)
            #expect(identity.file == directory.appendingPathComponent("main.swift").path)
            #expect(identity.offset > 0)
            #expect(unused.identity?.moduleName == "SafetyFixtures")
            #expect(report.warnings.contains { $0.contains("NSCopying") })

            try ReportService.write(report: report, to: directory.path)
            let restored = try ReportService.read(from: directory.path)
            #expect(restored.warnings == report.warnings)
            #expect(restored.unused == report.unused)
            #expect(restored.excluded == report.excluded)
            #expect(restored.options == report.options)
            #expect(restored.summary == report.summary)
            #expect(restored.version == report.version)
            let restoredWitness = try #require(restored.item(withId: witness.id))
            #expect(restoredWitness.identity == identity)
            #expect(restoredWitness.declaration.identity == identity)
            #expect(restored.item(withId: unused.id)?.identity == unused.identity)
        }
    }
}
