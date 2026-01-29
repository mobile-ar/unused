//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation
import Testing

@testable import unused

struct ReportServiceTests {

    @Test func testWriteReport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "testFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "testVariable",
                type: .variable,
                file: "/path/to/another.swift",
                line: 25,
                exclusionReason: .none,
                parentType: "TestClass"
            )
        ]

        let excluded = ExcludedItems(
            overrides: [],
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unusedItems,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)

        let outputPath = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: outputPath.path))

        let content = try String(contentsOf: outputPath, encoding: .utf8)
        #expect(content.contains("testFunction"))
        #expect(content.contains("testVariable"))
        #expect(content.contains("\"version\""))
    }

    @Test func testReadReport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "testFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "testVariable",
                type: .variable,
                file: "/path/to/another.swift",
                line: 25,
                exclusionReason: .override,
                parentType: "TestClass"
            )
        ]

        let excluded = ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [])

        let report = Report(
            unused: unusedItems,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 2)
        #expect(readReport.unused[0].id == 1)
        #expect(readReport.unused[0].name == "testFunction")
        #expect(readReport.unused[0].type == .function)
        #expect(readReport.unused[0].line == 10)
        #expect(readReport.unused[1].id == 2)
        #expect(readReport.unused[1].name == "testVariable")
        #expect(readReport.unused[1].type == .variable)
    }

    @Test func testReportExists() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        #expect(!ReportService.reportExists(in: tempDir.path))

        let report = Report(
            unused: [],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)

        #expect(ReportService.reportExists(in: tempDir.path))
    }

    @Test func testReadNonExistentFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        #expect(throws: Error.self) {
            try ReportService.read(from: tempDir.path)
        }
    }

    @Test func testEmptyReport() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let report = Report(
            unused: [],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.isEmpty)
        #expect(readReport.excluded.totalCount == 0)
    }

    @Test func testAllDeclarationTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "testFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "testVariable",
                type: .variable,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 3,
                name: "TestClass",
                type: .class,
                file: "/path/to/file.swift",
                line: 30,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 3)
        #expect(readReport.unused[0].type == .function)
        #expect(readReport.unused[1].type == .variable)
        #expect(readReport.unused[2].type == .class)
    }

    @Test func testAllExclusionReasons() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let excludedOverrides = [
            ReportItem(
                id: 1,
                name: "overrideMethod",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .override,
                parentType: nil
            )
        ]

        let excludedProtocols = [
            ReportItem(
                id: 2,
                name: "protocolMethod",
                type: .function,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .protocolImplementation,
                parentType: nil
            )
        ]

        let excludedObjc = [
            ReportItem(
                id: 3,
                name: "objcMethod",
                type: .function,
                file: "/path/to/file.swift",
                line: 30,
                exclusionReason: .objcAttribute,
                parentType: nil
            ),
            ReportItem(
                id: 4,
                name: "ibAction",
                type: .function,
                file: "/path/to/file.swift",
                line: 40,
                exclusionReason: .ibAction,
                parentType: nil
            ),
            ReportItem(
                id: 5,
                name: "ibOutlet",
                type: .variable,
                file: "/path/to/file.swift",
                line: 50,
                exclusionReason: .ibOutlet,
                parentType: nil
            )
        ]

        let excluded = ExcludedItems(
            overrides: excludedOverrides,
            protocolImplementations: excludedProtocols,
            objcItems: excludedObjc
        )

        let report = Report(
            unused: [],
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.excluded.overrides.count == 1)
        #expect(readReport.excluded.overrides[0].exclusionReason == .override)
        #expect(readReport.excluded.protocolImplementations.count == 1)
        #expect(readReport.excluded.protocolImplementations[0].exclusionReason == .protocolImplementation)
        #expect(readReport.excluded.objcItems.count == 3)
        #expect(readReport.excluded.objcItems[0].exclusionReason == .objcAttribute)
        #expect(readReport.excluded.objcItems[1].exclusionReason == .ibAction)
        #expect(readReport.excluded.objcItems[2].exclusionReason == .ibOutlet)
    }

    @Test func testReportOptionsPreserved() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let options = ReportOptions(
            includeOverrides: true,
            includeProtocols: false,
            includeObjc: true,
            includeTests: false
        )

        let report = Report(
            unused: [],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: options,
            testFilesExcluded: 5
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.options.includeOverrides == true)
        #expect(readReport.options.includeProtocols == false)
        #expect(readReport.options.includeObjc == true)
        #expect(readReport.options.includeTests == false)
        #expect(readReport.summary.testFilesExcluded == 5)
    }

    @Test func testItemLookupById() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let excludedOverrides = [
            ReportItem(
                id: 2,
                name: "overrideMethod",
                type: .function,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .override,
                parentType: nil
            )
        ]

        let excluded = ExcludedItems(
            overrides: excludedOverrides,
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unusedItems,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        // Should find unused item
        let item1 = readReport.item(withId: 1)
        #expect(item1 != nil)
        #expect(item1?.name == "unusedFunction")

        // Should find excluded item
        let item2 = readReport.item(withId: 2)
        #expect(item2 != nil)
        #expect(item2?.name == "overrideMethod")

        // Should return nil for non-existent ID
        let item3 = readReport.item(withId: 999)
        #expect(item3 == nil)
    }

    @Test func testMaxId() async throws {
        let unusedItems = [
            ReportItem(
                id: 1,
                name: "func1",
                type: .function,
                file: "/path/to/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "func2",
                type: .function,
                file: "/path/to/file.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let excludedOverrides = [
            ReportItem(
                id: 3,
                name: "override1",
                type: .function,
                file: "/path/to/file.swift",
                line: 30,
                exclusionReason: .override,
                parentType: nil
            )
        ]

        let excluded = ExcludedItems(
            overrides: excludedOverrides,
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unusedItems,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        #expect(report.maxId == 3)
    }

    @Test func testVersionIsSet() async throws {
        let report = Report(
            unused: [],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        #expect(report.version == Report.currentVersion)
        #expect(report.version == "1.0")
    }

    @Test func testSpecialCharactersInNames() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "test\"Function",
                type: .function,
                file: "/path/to/\"file\".swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "test,Function",
                type: .function,
                file: "/path/to/file,with,commas.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 2)
        #expect(readReport.unused[0].name == "test\"Function")
        #expect(readReport.unused[0].file == "/path/to/\"file\".swift")
        #expect(readReport.unused[1].name == "test,Function")
        #expect(readReport.unused[1].file == "/path/to/file,with,commas.swift")
    }

}
