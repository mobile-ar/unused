import Foundation
import Testing
@testable import unused

struct GeneratedDependencyIntegrationTests {
    private static let swiftInterface = """
        public protocol Equatable { static func == (_ lhs: Self, _ rhs: Self) -> Bool }
        public protocol Hashable: Swift.Equatable { func hash(into hasher: inout Swift.Hasher) }
        public protocol Encodable { func encode(to encoder: any Swift.Encoder) throws }
        public protocol Decodable { init(from decoder: any Swift.Decoder) throws }
        public typealias Codable = Swift.Encodable & Swift.Decodable
        public protocol CodingKey {}
        public protocol CaseIterable { associatedtype AllCases; static var allCases: Self.AllCases { get } }
        public struct Int {}
        public struct String {}
        """

    private func analyze(_ sources: [String: String], options: AnalyzerOptions = AnalyzerOptions()) async throws -> Report {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratedDependencies-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try sources.sorted(by: { $0.key < $1.key }).map { name, source in
            let file = directory.appendingPathComponent(name)
            try source.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let client = SwiftInterfaceClient(moduleInterfaceProvider: { module in
            if module == "Swift" { return Self.swiftInterface }
            if module == "Foundation" { return "open class NSObject {}" }
            return nil
        })
        let analyzer = SwiftAnalyzer(options: options, directory: directory.path, swiftInterfaceClient: client,
                                     moduleName: "App", progressTrackerFactory: { total, prefix in
            ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
        })
        let report = await analyzer.analyzeFiles(files)
        let persisted = try ReportService.read(from: directory.path)
        #expect(persisted.unused == report.unused)
        #expect(persisted.excluded == report.excluded)
        #expect(persisted.warnings == report.warnings)
        #expect(persisted.summary == report.summary)
        return report
    }

    @Test
    func synthesizedReadsAreNotUnusedOrWriteOnlyWhileComputedAndStaticBindingsRemainCandidates() async throws {
        let report = try await analyze(["Model.swift": """
            struct Model: Hashable {
                var value = 0
                var computed: Int { 0 }
                static var shared = 0
            }
            var model = Model()
            model.value = 1
            """])
        #expect(!report.unused.contains { $0.name == "value" })
        #expect(report.unused.contains { $0.name == "computed" })
        #expect(report.unused.contains { $0.name == "shared" })
    }

    @Test
    func codingKeysMembershipAndManualWitnessesRemainIndependentAcrossFiles() async throws {
        let report = try await analyze([
            "Model.swift": """
                struct Model: Codable {
                    var included = 0
                    var omitted = 0
                    let defaulted = 0
                    enum CodingKeys: String, CodingKey { case included }
                }
                struct Manual: Codable {
                    var unused = 0
                    enum CodingKeys: String, CodingKey { case unusedKey }
                    func encode(to encoder: any Encoder) throws {}
                    init(from decoder: any Decoder) throws { unused = 0 }
                }
                """,
            "Encoding.swift": "extension Model { func encode(to encoder: any Encoder) throws {} }"
        ])
        #expect(!report.unused.contains { $0.name == "included" })
        #expect(!report.unused.contains { $0.name == "CodingKeys" && $0.parentType == "Model" })
        #expect(report.unused.contains { $0.name == "omitted" })
        #expect(report.unused.contains { $0.name == "defaulted" })
        #expect(report.unused.contains { $0.name == "unusedKey" })
        #expect(report.unused.contains { $0.name == "CodingKeys" && $0.parentType == "Manual" })
    }

    @Test
    func enumCompilerPathsProtectOnlyApplicableCases() async throws {
        let report = try await analyze([
            "Enums.swift": """
                protocol Iterable: Swift.CaseIterable {}
                typealias Iteration = Iterable
                enum Season: Iteration { case spring, winter }
                enum Status: Int { case ready = 1, finished = 2 }
                enum Manual: CaseIterable {
                    case first, unused
                    static var allCases: [Self] { [.first] }
                }
                enum Ordinary { case unusedOrdinary }
                """,
            "main.swift": "let status = App.Status(rawValue: 1)"
        ])
        #expect(!report.unused.contains { ["spring", "winter", "ready", "finished"].contains($0.name) })
        #expect(report.unused.contains { $0.name == "unused" && $0.type == .enumCase })
        #expect(report.unused.contains { $0.name == "unusedOrdinary" })
    }

    @Test
    func wrapperLoweringProtectsHooksAndParametersButNotUnusedProjectionOrOverloads() async throws {
        let report = try await analyze(["Wrapper.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                var projectedValue: Int { 0 }
                init(wrappedValue: Int) { self.wrappedValue = 0 }
                init(other: String) { wrappedValue = 0; print(other) }
            }
            struct Model { @Box var value: Int = 1 }
            let model = Model()
            print(model.value)
            """])
        #expect(!report.unused.contains { $0.name == "wrappedValue" })
        #expect(!report.unused.contains { $0.name == "init" && $0.identity?.signature.parameterLabels == ["wrappedValue"] })
        #expect(report.unused.contains { $0.name == "projectedValue" })
        #expect(report.unused.contains { $0.name == "init" && $0.identity?.signature.parameterLabels == ["other"] })
        #expect(!report.warnings.contains { $0.contains("macro") })
    }

    @Test
    func wrapperProjectionIsAnImplicitUseRatherThanANameOnlyReference() async throws {
        let report = try await analyze(["Wrapper.swift": """
            @propertyWrapper struct Box {
                var wrappedValue: Int
                var projectedValue: Int { 0 }
                init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
            }
            struct Model { @Box var value: Int = 1 }
            let model = Model()
            print(model.$value)
            """])
        #expect(!report.unused.contains { $0.name == "projectedValue" || $0.name == "value" })
    }

    @Test
    func runtimeExposureAndPropertyOverridesSurviveWithoutSwiftReferences() async throws {
        let report = try await analyze([
            "Runtime.swift": """
                import Foundation
                @objc(RuntimeNamed) class Named: NSObject {}
                @objcMembers class Base: NSObject {
                    var value = 0
                    @nonobjc var swiftOnly = 0
                    func callback(_ sender: NSObject) {}
                }
                class Child: Base {
                    override var description: String { "child" }
                    dynamic var dynamicValue = 0
                    @objc var key = 0
                    @NSManaged var managed: String
                }
                """,
            "Extension.swift": "extension Child { var extensionValue: Int { 0 } }",
            "main.swift": """
                import Foundation
                func runtimeUse(_ object: Child) {
                    object.perform(#selector(Base.callback(_:)))
                    object.setValue(1, forKey: "key")
                    object.addObserver(object, forKeyPath: "value", options: [], context: nil)
                }
                """
        ])
        for name in ["Named", "dynamicValue", "key", "managed", "extensionValue"] {
            #expect(report.excluded.objcItems.contains { $0.name == name })
            #expect(!report.unused.contains { $0.name == name })
        }
        #expect(report.excluded.overrides.contains { $0.name == "description" && $0.type == .variable })
        #expect(report.unused.contains { $0.name == "swiftOnly" })
        #expect(!report.unused.contains { $0.name == "sender" && $0.type == .parameter })
    }

    @Test
    func knownSchemaUsesAndUnsupportedMacroUncertaintyAreReportedSeparately() async throws {
        let report = try await analyze(["Macros.swift": """
            @Model class Record {
                var title = ""
                @Transient var scratch = 0
                var computed: Int { 0 }
                static var shared = 0
            }
            @Generate struct Unknown {
                var value = 0
                func generatedCallback(_ argument: Int) {}
                struct Nested { var unrelated = 0 }
            }
            var record = Record()
            record.title = "updated"
            """])
        #expect(!report.unused.contains { $0.name == "title" })
        for name in ["scratch", "computed", "shared", "unrelated"] {
            #expect(report.unused.contains { $0.name == name })
        }
        #expect(report.excluded.macroItems.contains { $0.name == "value" && $0.exclusionReason == .unresolvedMacro })
        #expect(!report.unused.contains { $0.name == "argument" })
        #expect(report.warnings.contains { $0.contains("Unsupported attached macro @Generate") })
        var output: [String] = []
        ReportService.display(report: report, output: { output.append($0) })
        #expect(output.contains { $0.contains("potential macro dependency") })
        #expect(report.summary.totalExcluded == report.excluded.allItems.count)
    }

    @Test
    func unsupportedMacroUncertaintyCannotBeBypassedByRuntimeInclusionFlags() async throws {
        let options = AnalyzerOptions(includeOverrides: true, includeObjc: true, showExcluded: true)
        let report = try await analyze(["Overlap.swift": """
            class Base { var callback: Int { 0 } }
            @Generate class Child: Base {
                override var callback: Int { 1 }
                @objc var exposed = 0
            }
            """], options: options)
        for name in ["callback", "exposed"] {
            #expect(!report.unused.contains { $0.parentType == "Child" && $0.name == name })
            #expect(report.excluded.macroItems.contains {
                $0.parentType == "Child" && $0.name == name && $0.exclusionReason == .unresolvedMacro
            })
        }
        var output: [String] = []
        ReportService.display(report: report, output: { output.append($0) })
        #expect(output.contains { $0.contains("Unresolved Macro Dependencies:") })
        #expect(output.contains { $0.contains("[unresolved macro]") && $0.contains("exposed") })
    }

    @Test
    func enumAssociatedValueKeysAreProtectedInReports() async throws {
        let report = try await analyze(["Event.swift": """
            enum Event: Codable {
                case message(text: String)
                enum MessageCodingKeys: String, CodingKey { case text = "body" }
                enum UnrelatedCodingKeys: String, CodingKey { case unused }
            }
            """])
        #expect(!report.unused.contains { $0.name == "MessageCodingKeys" || $0.name == "text" })
        #expect(report.unused.contains { $0.name == "UnrelatedCodingKeys" })
        #expect(report.unused.contains { $0.name == "unused" })
    }

    @Test
    func inclusionOptionsStillApplyToRuntimeProperties() async throws {
        let options = AnalyzerOptions(includeOverrides: true, includeObjc: true)
        let report = try await analyze(["Runtime.swift": """
            class Base { var callback: Int { 0 } }
            class Child: Base {
                override var callback: Int { 1 }
                @objc var exposed = 0
            }
            """], options: options)
        #expect(report.unused.contains { $0.parentType == "Child" && $0.name == "callback" && $0.exclusionReason == .override })
        #expect(report.unused.contains { $0.name == "exposed" && $0.exclusionReason == .objcAttribute })
        #expect(report.excluded.overrides.isEmpty)
        #expect(report.excluded.objcItems.isEmpty)
    }
}
