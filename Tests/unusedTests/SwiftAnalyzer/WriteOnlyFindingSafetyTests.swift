import Foundation
import Testing
@testable import unused

struct WriteOnlyFindingSafetyTests {
    private func analyze(_ source: String, options: AnalyzerOptions = AnalyzerOptions()) async throws -> Report {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Subject.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let analyzer = SwiftAnalyzer(
            options: options, directory: directory.path,
            swiftInterfaceClient: SwiftInterfaceClient(moduleInterfaceProvider: { _ in nil }),
            progressTrackerFactory: { total, prefix in
                ProgressTracker(total: total, prefix: prefix, render: { _ in }, finishLine: {})
            }
        )
        return await analyzer.analyzeFiles([file])
    }

    @Test
    func requiredPropertyKeepsItsExclusionEvenWhenOnlyWritten() async throws {
        let source = """
        protocol Required { var value: Int { get set } }
        struct Subject: Required {
            var value: Int
            init() { self.value = 1 }
        }
        """
        let report = try await analyze(source)
        #expect(!report.unused.contains { $0.name == "value" && $0.type == .variable })
        #expect(report.excluded.protocolImplementations.contains { $0.name == "value" && $0.exclusionReason == .protocolImplementation && $0.isWriteOnly })
        let included = try await analyze(source, options: AnalyzerOptions(includeProtocols: true))
        let property = try #require(included.unused.first { $0.name == "value" && $0.type == .variable })
        #expect(property.isWriteOnly)
        #expect(property.exclusionReason == .protocolImplementation)
    }

    @Test
    func overrideWriteOnlyPropertyRespectsOptionAndPreservesReason() async throws {
        let source = """
        class Base { var value: Int { get { 0 } set {} } }
        class Subject: Base {
            override var value: Int { get { 0 } set {} }
            func update() { self.value = 1 }
        }
        """
        let report = try await analyze(source)
        #expect(!report.unused.contains { $0.name == "value" && $0.parentType == "Subject" })
        #expect(report.excluded.overrides.contains { $0.name == "value" && $0.parentType == "Subject" && $0.isWriteOnly })
        let included = try await analyze(source, options: AnalyzerOptions(includeOverrides: true))
        let property = try #require(included.unused.first { $0.name == "value" && $0.parentType == "Subject" })
        #expect(property.isWriteOnly)
        #expect(property.exclusionReason == .override)
    }

    @Test(arguments: ["@objc", "dynamic", "@objcMembers"])
    func runtimeExposureWriteOnlyPropertiesRespectObjcPolicy(_ exposure: String) async throws {
        let source = """
        \(exposure == "@objcMembers" ? exposure : "") class Subject {
            \(exposure == "@objcMembers" ? "" : exposure) var value: Int
            init() { self.value = 1 }
        }
        """
        let report = try await analyze(source)
        #expect(!report.unused.contains { $0.name == "value" && $0.type == .variable })
        #expect(report.excluded.objcItems.contains { $0.name == "value" })
        let included = try await analyze(source, options: AnalyzerOptions(includeObjc: true))
        let property = try #require(included.unused.first { $0.name == "value" && $0.type == .variable })
        #expect(property.isWriteOnly)
        #expect(property.exclusionReason == .objcAttribute)
    }

    @Test
    func unresolvedWitnessRemainsExcludedWithEveryOptIn() async throws {
        let report = try await analyze("""
        struct Subject: MissingProtocol {
            var value: Int
            init() { self.value = 1 }
        }
        """, options: AnalyzerOptions(includeOverrides: true, includeProtocols: true, includeObjc: true))
        #expect(!report.unused.contains { $0.name == "value" && $0.type == .variable })
        #expect(report.excluded.protocolImplementations.contains { $0.name == "value" && $0.exclusionReason == .unresolvedProtocol && $0.isWriteOnly })
    }

    @Test
    func unresolvedMacroRemainsExcludedWithEveryOptIn() async throws {
        let report = try await analyze("""
        @UnknownMacro struct Subject {
            var value: Int
            init() { self.value = 1 }
        }
        """, options: AnalyzerOptions(includeOverrides: true, includeProtocols: true, includeObjc: true))
        #expect(!report.unused.contains { $0.name == "value" && $0.type == .variable })
        #expect(report.excluded.macroItems.contains { $0.name == "value" && $0.exclusionReason == .unresolvedMacro && $0.isWriteOnly })
    }

    @Test(arguments: ["@NSManaged", "@IBOutlet", "@IBInspectable", "@Wrapper"])
    func managedPropertiesDoNotBecomeWriteOnlyCandidates(_ attribute: String) async throws {
        let report = try await analyze("""
        @propertyWrapper struct Wrapper { var wrappedValue: Int }
        class Subject {
            \(attribute) var value: Int
            init() { self.value = 1 }
        }
        """, options: AnalyzerOptions(includeObjc: true))
        #expect(!report.unused.contains { $0.name == "value" && $0.type == .variable })
    }

    @Test
    func assignmentIndexAndReceiverReadsPreventWriteOnlyFindings() async throws {
        let report = try await analyze("""
        struct Subject {
            var items: [Int]
            var index: Int
            var receiver: Subject?
            init() { items = []; index = 0; receiver = nil }
            func update() { self.items[self.index] = 1; self.receiver?.index = 2 }
        }
        """)
        #expect(!report.unused.contains { $0.type == .variable && ["items", "index", "receiver"].contains($0.name) })
    }
}
