//
//  Created by Fernando Romiti on 25/01/2026.
//

import Foundation
import Testing

@testable import unused

struct ReportTests {

    // MARK: - ReportItem Tests

    @Test func testReportItemInitFromDeclaration() async throws {
        let declaration = Declaration(
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 42,
            exclusionReason: .override,
            parentType: "TestClass"
        )

        let reportItem = ReportItem(id: 1, declaration: declaration)

        #expect(reportItem.id == 1)
        #expect(reportItem.name == "testFunction")
        #expect(reportItem.type == .function)
        #expect(reportItem.file == "/path/to/file.swift")
        #expect(reportItem.line == 42)
        #expect(reportItem.exclusionReason == .override)
        #expect(reportItem.parentType == "TestClass")
    }

    @Test func testReportItemToDeclaration() async throws {
        let reportItem = ReportItem(
            id: 1,
            name: "testFunction",
            type: .function,
            file: "/path/to/file.swift",
            line: 42,
            exclusionReason: .protocolImplementation,
            parentType: "TestClass"
        )

        let declaration = reportItem.declaration

        #expect(declaration.name == "testFunction")
        #expect(declaration.type == .function)
        #expect(declaration.file == "/path/to/file.swift")
        #expect(declaration.line == 42)
        #expect(declaration.exclusionReason == .protocolImplementation)
        #expect(declaration.parentType == "TestClass")
    }

    @Test func testReportItemCodable() async throws {
        let reportItem = ReportItem(
            id: 5,
            name: "codableTest",
            type: .variable,
            file: "/path/to/file.swift",
            line: 100,
            exclusionReason: .ibOutlet,
            parentType: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(reportItem)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportItem.self, from: data)

        #expect(decoded == reportItem)
    }

    @Test func testReportItemEquatable() async throws {
        let item1 = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: "/path.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let item2 = ReportItem(
            id: 1,
            name: "test",
            type: .function,
            file: "/path.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        let item3 = ReportItem(
            id: 2,
            name: "test",
            type: .function,
            file: "/path.swift",
            line: 10,
            exclusionReason: .none,
            parentType: nil
        )

        #expect(item1 == item2)
        #expect(item1 != item3)
    }

    // MARK: - ExcludedItems Tests

    @Test func testExcludedItemsTotalCount() async throws {
        let overrides = [
            ReportItem(id: 1, name: "o1", type: .function, file: "/f.swift", line: 1, exclusionReason: .override, parentType: nil),
            ReportItem(id: 2, name: "o2", type: .function, file: "/f.swift", line: 2, exclusionReason: .override, parentType: nil)
        ]

        let protocols = [
            ReportItem(id: 3, name: "p1", type: .function, file: "/f.swift", line: 3, exclusionReason: .protocolImplementation, parentType: nil)
        ]

        let objc = [
            ReportItem(id: 4, name: "obj1", type: .function, file: "/f.swift", line: 4, exclusionReason: .objcAttribute, parentType: nil),
            ReportItem(id: 5, name: "obj2", type: .function, file: "/f.swift", line: 5, exclusionReason: .ibAction, parentType: nil),
            ReportItem(id: 6, name: "obj3", type: .variable, file: "/f.swift", line: 6, exclusionReason: .ibOutlet, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: overrides,
            protocolImplementations: protocols,
            objcItems: objc
        )

        #expect(excluded.totalCount == 6)
    }

    @Test func testExcludedItemsAllItems() async throws {
        let overrides = [
            ReportItem(id: 1, name: "o1", type: .function, file: "/f.swift", line: 1, exclusionReason: .override, parentType: nil)
        ]

        let protocols = [
            ReportItem(id: 2, name: "p1", type: .function, file: "/f.swift", line: 2, exclusionReason: .protocolImplementation, parentType: nil)
        ]

        let objc = [
            ReportItem(id: 3, name: "obj1", type: .function, file: "/f.swift", line: 3, exclusionReason: .objcAttribute, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: overrides,
            protocolImplementations: protocols,
            objcItems: objc
        )

        let allItems = excluded.allItems

        #expect(allItems.count == 3)
        #expect(allItems[0].id == 1)
        #expect(allItems[1].id == 2)
        #expect(allItems[2].id == 3)
    }

    @Test func testExcludedItemsEmpty() async throws {
        let excluded = ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [])

        #expect(excluded.overrides.isEmpty)
        #expect(excluded.protocolImplementations.isEmpty)
        #expect(excluded.objcItems.isEmpty)
        #expect(excluded.totalCount == 0)
        #expect(excluded.allItems.isEmpty)
    }

    @Test func testExcludedItemsCodable() async throws {
        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 1, name: "o1", type: .function, file: "/f.swift", line: 1, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [
                ReportItem(id: 2, name: "p1", type: .function, file: "/f.swift", line: 2, exclusionReason: .protocolImplementation, parentType: nil)
            ],
            objcItems: []
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(excluded)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExcludedItems.self, from: data)

        #expect(decoded == excluded)
    }

    // MARK: - ReportSummary Tests

    @Test func testReportSummaryCodable() async throws {
        let summary = ReportSummary(
            totalExcluded: 25,
            testFilesExcluded: 5
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(summary)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportSummary.self, from: data)

        #expect(decoded == summary)
    }

    // MARK: - ReportOptions Tests

    @Test func testReportOptionsFromAnalyzerOptions() async throws {
        let analyzerOptions = AnalyzerOptions(
            includeOverrides: true,
            includeProtocols: false,
            includeObjc: true,
            showExcluded: true,
            includeTests: false
        )

        let reportOptions = ReportOptions(from: analyzerOptions)

        #expect(reportOptions.includeOverrides == true)
        #expect(reportOptions.includeProtocols == false)
        #expect(reportOptions.includeObjc == true)
        #expect(reportOptions.includeTests == false)
    }

    @Test func testReportOptionsDefaults() async throws {
        let options = ReportOptions()

        #expect(options.includeOverrides == false)
        #expect(options.includeProtocols == false)
        #expect(options.includeObjc == false)
        #expect(options.includeTests == false)
    }

    @Test func testReportOptionsCodable() async throws {
        let options = ReportOptions(
            includeOverrides: true,
            includeProtocols: true,
            includeObjc: false,
            includeTests: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(options)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReportOptions.self, from: data)

        #expect(decoded == options)
    }

    // MARK: - Report Tests

    @Test func testReportInit() async throws {
        let unused = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/f.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "var1", type: .variable, file: "/f.swift", line: 2, exclusionReason: .none, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 3, name: "o1", type: .function, file: "/f.swift", line: 3, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [],
            objcItems: []
        )

        let options = ReportOptions(includeOverrides: false, includeProtocols: true)

        let report = Report(
            unused: unused,
            excluded: excluded,
            options: options,
            testFilesExcluded: 3
        )

        #expect(report.version == Report.currentVersion)
        #expect(report.unused.count == 2)
        #expect(report.excluded.totalCount == 1)
        #expect(report.summary.totalExcluded == 1)
        #expect(report.summary.testFilesExcluded == 3)
        #expect(report.options.includeOverrides == false)
        #expect(report.options.includeProtocols == true)
    }

    @Test func testReportAllItems() async throws {
        let unused = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/f.swift", line: 1, exclusionReason: .none, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 2, name: "o1", type: .function, file: "/f.swift", line: 2, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [
                ReportItem(id: 3, name: "p1", type: .function, file: "/f.swift", line: 3, exclusionReason: .protocolImplementation, parentType: nil)
            ],
            objcItems: []
        )

        let report = Report(
            unused: unused,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let allItems = report.allItems

        #expect(allItems.count == 3)
    }

    @Test func testReportItemWithId() async throws {
        let unused = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/f.swift", line: 1, exclusionReason: .none, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 2, name: "o1", type: .function, file: "/f.swift", line: 2, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unused,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let item1 = report.item(withId: 1)
        #expect(item1 != nil)
        #expect(item1?.name == "func1")

        let item2 = report.item(withId: 2)
        #expect(item2 != nil)
        #expect(item2?.name == "o1")

        let item3 = report.item(withId: 999)
        #expect(item3 == nil)
    }

    @Test func testReportMaxId() async throws {
        let unused = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/f.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 5, name: "func2", type: .function, file: "/f.swift", line: 2, exclusionReason: .none, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 10, name: "o1", type: .function, file: "/f.swift", line: 3, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unused,
            excluded: excluded,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        #expect(report.maxId == 10)
    }

    @Test func testReportMaxIdEmpty() async throws {
        let report = Report(
            unused: [],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        #expect(report.maxId == 0)
    }

    @Test func testReportCodable() async throws {
        let unused = [
            ReportItem(id: 1, name: "func1", type: .function, file: "/f.swift", line: 1, exclusionReason: .none, parentType: nil)
        ]

        let excluded = ExcludedItems(
            overrides: [
                ReportItem(id: 2, name: "o1", type: .function, file: "/f.swift", line: 2, exclusionReason: .override, parentType: nil)
            ],
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unused,
            excluded: excluded,
            options: ReportOptions(includeOverrides: true),
            testFilesExcluded: 5
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Report.self, from: data)

        #expect(decoded.version == report.version)
        #expect(decoded.unused.count == report.unused.count)
        #expect(decoded.excluded.totalCount == report.excluded.totalCount)
        #expect(decoded.summary == report.summary)
        #expect(decoded.options == report.options)
    }

    @Test func testReportCurrentVersion() async throws {
        #expect(Report.currentVersion == "1.0")
    }

    @Test func testDeclarationTypeCodable() async throws {
        let types: [DeclarationType] = [.function, .variable, .class]

        let encoder = JSONEncoder()
        let data = try encoder.encode(types)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([DeclarationType].self, from: data)

        #expect(decoded == types)
    }

    @Test func testExclusionReasonCodable() async throws {
        let reasons: [ExclusionReason] = [.override, .protocolImplementation, .objcAttribute, .ibAction, .ibOutlet, .none]

        let encoder = JSONEncoder()
        let data = try encoder.encode(reasons)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ExclusionReason].self, from: data)

        #expect(decoded == reasons)
    }

}
