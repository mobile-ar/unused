import ArgumentParser
import Foundation
import Testing
@testable import unused

struct GraphCommandTests {
    @Test func parsesGraphOptionsAndRegistersTheSubcommand() throws {
        let command = try #require(try Unused.parseAsRoot([
            "graph", "42", "/project", "--depth", "3", "--limit", "5", "--width", "72",
            "--include-tests", "--ascii", "--no-color", "--outbound-only"
        ]) as? Graph)
        #expect(command.id == 42)
        #expect(command.directory == "/project")
        #expect(command.depth == 3)
        #expect(command.limit == 5)
        #expect(command.width == 72)
        #expect(command.includeTests)
        #expect(command.ascii)
        #expect(command.noColor)
        #expect(command.outboundOnly)
        #expect(!command.inboundOnly)
    }

    @Test func defaultsAreBoundedAndRespectReportScope() throws {
        let command = try #require(try Unused.parseAsRoot(["graph", "1"]) as? Graph)
        #expect(command.depth == 1)
        #expect(command.limit == 20)
        #expect(command.width == nil)
        #expect(!command.includeTests)
        #expect(!command.ascii)
    }

    @Test(arguments: [
        ["0"], ["1", "--inbound-only", "--outbound-only"], ["1", "--depth", "0"],
        ["1", "--depth", "11"], ["1", "--limit", "0"], ["1", "--limit", "1001"],
        ["1", "--width", "19"], ["1", "--width", "301"]
    ])
    func rejectsInvalidOptions(arguments: [String]) {
        #expect(throws: (any Error).self) {
            _ = try Unused.parseAsRoot(["graph"] + arguments)
        }
    }

    @Test func missingReportIsActionable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let command = try Graph.parse(["1", directory])
        await #expect(throws: ValidationError.self) {
            try await command.run()
        }
    }

    @Test func commandIsReadOnlyAndDoesNotChangeGlobalOutputSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Main.swift")
        let source = "func target() { helper() }\nfunc helper() {}\nfunc caller() { target() }"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let report = Report(
            unused: [ReportItem(id: 1, name: "target", type: .function, file: file.path, line: 1, exclusionReason: .none, parentType: nil)],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(includeTests: true), testFilesExcluded: 0
        )
        try ReportService.write(report: report, to: directory.path)
        let reportURL = directory.appendingPathComponent(ReportService.reportFileName)
        let originalReport = try Data(contentsOf: reportURL)
        let colorEnabled = OutputConfig.colorEnabled
        let interactiveEnabled = OutputConfig.interactiveEnabled
        let command = try Graph.parse(["1", directory.path, "--no-color", "--ascii", "--outbound-only", "--depth", "2"])
        try await command.run()
        #expect(try Data(contentsOf: reportURL) == originalReport)
        #expect(try String(contentsOf: file, encoding: .utf8) == source)
        #expect(OutputConfig.colorEnabled == colorEnabled)
        #expect(OutputConfig.interactiveEnabled == interactiveEnabled)
    }

    @Test(arguments: [DeclarationType.parameter, .import])
    func rejectsFindingsWithoutIndependentGraphs(type: DeclarationType) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = Report(
            unused: [ReportItem(id: 1, name: "target", type: type, file: "Main.swift", line: 1, exclusionReason: .none, parentType: nil)],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(), testFilesExcluded: 0
        )
        try ReportService.write(report: report, to: directory.path)
        var command = try Graph.parse(["1", directory.path])
        await #expect(throws: ValidationError.self) {
            try await command.run()
        }
        command.id = 999
        await #expect(throws: ValidationError.self) {
            try await command.run()
        }
    }
}
