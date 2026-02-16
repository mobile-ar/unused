//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct OpenCommandTests {

    @Test func testReportWorkflowForOpenCommand() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("test.swift")
        try "// test file".write(to: testFile, atomically: true, encoding: .utf8)

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "testFunction",
                type: .function,
                file: testFile.path,
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)

        let readReport = try ReportService.read(from: tempDir.path)
        #expect(readReport.unused.count == 1)
        #expect(readReport.unused[0].name == "testFunction")
        #expect(readReport.unused[0].file == testFile.path)
    }

    @Test func testReadReportForOpenCommand() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "firstFunction",
                type: .function,
                file: "/path/to/file1.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "secondFunction",
                type: .function,
                file: "/path/to/file2.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 3,
                name: "thirdFunction",
                type: .function,
                file: "/path/to/file3.swift",
                line: 30,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 3)

        let entry = readReport.item(withId: 2)
        #expect(entry != nil)
        #expect(entry?.name == "secondFunction")
        #expect(entry?.file == "/path/to/file2.swift")
        #expect(entry?.line == 20)
    }

    @Test func testInvalidIDLookup() async throws {
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
                line: 1,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        let entry = readReport.item(withId: 999)
        #expect(entry == nil)
    }

    @Test func testValidIDLookup() async throws {
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
                line: 42,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        let entry = readReport.item(withId: 1)
        #expect(entry != nil)
        #expect(entry?.name == "testFunction")
        #expect(entry?.line == 42)
    }

    @Test func testMultipleDeclarationsIDSequence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/file1.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "func2", type: .function, file: "/file2.swift", line: 2, exclusionReason: .none, parentType: nil),
            ReportItem(id: 3, name: "func3", type: .function, file: "/file3.swift", line: 3, exclusionReason: .none, parentType: nil),
            ReportItem(id: 4, name: "func4", type: .function, file: "/file4.swift", line: 4, exclusionReason: .none, parentType: nil),
            ReportItem(id: 5, name: "func5", type: .function, file: "/file5.swift", line: 5, exclusionReason: .none, parentType: nil)
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 5)

        for i in 1...5 {
            let entry = readReport.item(withId: i)
            #expect(entry != nil)
            #expect(entry?.name == "func\(i)")
            #expect(entry?.line == i)
        }
    }

    @Test func testExcludedItemsIDLookup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(id: 1, name: "unusedFunc", type: .function, file: "/file1.swift", line: 10, exclusionReason: .none, parentType: nil)
        ]

        let excludedItems = ExcludedItems(
            overrides: [
                ReportItem(id: 2, name: "overrideFunc", type: .function, file: "/file2.swift", line: 20, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [
                ReportItem(id: 3, name: "protocolFunc", type: .function, file: "/file3.swift", line: 30, exclusionReason: .protocolImplementation, parentType: nil)
            ],
            objcItems: [],
            mainTypes: []
        )

        let report = Report(
            unused: unusedItems,
            excluded: excludedItems,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        // Should find unused item
        let entry1 = readReport.item(withId: 1)
        #expect(entry1 != nil)
        #expect(entry1?.name == "unusedFunc")

        // Should find excluded override
        let entry2 = readReport.item(withId: 2)
        #expect(entry2 != nil)
        #expect(entry2?.name == "overrideFunc")
        #expect(entry2?.exclusionReason == .override)

        // Should find excluded protocol implementation
        let entry3 = readReport.item(withId: 3)
        #expect(entry3 != nil)
        #expect(entry3?.name == "protocolFunc")
        #expect(entry3?.exclusionReason == .protocolImplementation)
    }

}
