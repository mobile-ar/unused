//
//  Created by Fernando Romiti on 05/12/2025.
//

import Testing
import Foundation
@testable import unused

struct IntegrationTests {

    @Test func testCompleteWorkflow() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("Test.swift")
        let swiftContent = """
        class TestClass {
            func usedFunction() {
                print("Hello")
            }

            func unusedFunction() {
                print("Never called")
            }

            var usedVariable = "used"
            var unusedVariable = "unused"
        }

        let instance = TestClass()
        instance.usedFunction()
        print(instance.usedVariable)
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let unusedFilePath = tempDir.appendingPathComponent(ReportService.reportFileName)
        #expect(FileManager.default.fileExists(atPath: unusedFilePath.path))

        let jsonContent = try String(contentsOf: unusedFilePath, encoding: .utf8)
        #expect(jsonContent.contains("\"version\""))
        #expect(jsonContent.contains("\"unused\""))

        let report = try ReportService.read(from: tempDir.path)
        #expect(report.unused.count > 0 || report.excluded.totalCount > 0)

        let hasUnusedFunction = report.unused.contains { $0.name.contains("unused") && $0.type == .function }
        let hasUnusedVariable = report.unused.contains { $0.name.contains("unused") && $0.type == .variable }

        #expect(hasUnusedFunction || hasUnusedVariable)
    }

    @Test func testReportPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "testFunc1",
                type: .function,
                file: "/test/file1.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "testVar",
                type: .variable,
                file: "/test/file3.swift",
                line: 30,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let excludedItems = ExcludedItems(
            overrides: [
                ReportItem(
                    id: 3,
                    name: "testFunc2",
                    type: .function,
                    file: "/test/file2.swift",
                    line: 20,
                    exclusionReason: .override,
                    parentType: "MyClass"
                )
            ],
            protocolImplementations: [],
            objcItems: []
        )

        let report = Report(
            unused: unusedItems,
            excluded: excludedItems,
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)

        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 2)
        #expect(readReport.excluded.overrides.count == 1)

        #expect(readReport.unused[0].id == 1)
        #expect(readReport.unused[0].name == "testFunc1")
        #expect(readReport.unused[0].type == .function)
        #expect(readReport.unused[0].file == "/test/file1.swift")
        #expect(readReport.unused[0].line == 10)

        #expect(readReport.excluded.overrides[0].id == 3)
        #expect(readReport.excluded.overrides[0].name == "testFunc2")
        #expect(readReport.excluded.overrides[0].exclusionReason == .override)
        #expect(readReport.excluded.overrides[0].parentType == "MyClass")
    }

    @Test func testOpenCommandWorkflow() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testFile = tempDir.appendingPathComponent("RealFile.swift")
        try "// Real Swift File\nfunc realFunction() {}\n".write(to: testFile, atomically: true, encoding: .utf8)

        let unusedItems = [
            ReportItem(
                id: 1,
                name: "realFunction",
                type: .function,
                file: testFile.path,
                line: 2,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "anotherFunction",
                type: .function,
                file: testFile.path,
                line: 3,
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

        let firstEntry = readReport.item(withId: 1)
        #expect(firstEntry != nil)
        #expect(firstEntry?.name == "realFunction")
        #expect(firstEntry?.file == testFile.path)
        #expect(firstEntry?.line == 2)

        let secondEntry = readReport.item(withId: 2)
        #expect(secondEntry != nil)
        #expect(secondEntry?.name == "anotherFunction")
    }

    @Test func testUnusedEnumCasesDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("Enums.swift")
        let swiftContent = """
        enum Direction {
            case north
            case south
            case east
            case west
        }

        func navigate() {
            let dir = Direction.north
            switch dir {
            case .south:
                print("south")
            default:
                break
            }
        }
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedEnumCases = report.unused.filter { $0.type == .enumCase }

        // "north" is used via Direction.north, "south" via .south in switch
        // "east" and "west" are never referenced
        #expect(unusedEnumCases.contains { $0.name == "east" })
        #expect(unusedEnumCases.contains { $0.name == "west" })
        #expect(!unusedEnumCases.contains { $0.name == "north" })
        #expect(!unusedEnumCases.contains { $0.name == "south" })
    }

    @Test func testUnusedProtocolDeclarationDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("Protocols.swift")
        let swiftContent = """
        protocol UsedProtocol {
            func doWork()
        }

        protocol UnusedProtocol {
            func doNothing()
        }

        class Worker: UsedProtocol {
            func doWork() {
                print("working")
            }
        }

        let worker = Worker()
        worker.doWork()
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedProtocols = report.unused.filter { $0.type == .protocol }
        #expect(unusedProtocols.contains { $0.name == "UnusedProtocol" })
        #expect(!unusedProtocols.contains { $0.name == "UsedProtocol" })
    }

    @Test func testCaseIterableEnumCasesExcluded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("CaseIterable.swift")
        let swiftContent = """
        enum Season: CaseIterable {
            case spring
            case summer
            case autumn
            case winter
        }

        let allSeasons = Season.allCases
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        // CaseIterable enum cases should be excluded (not in unused)
        let unusedEnumCases = report.unused.filter { $0.type == .enumCase }
        #expect(unusedEnumCases.isEmpty)
    }

    @Test func testCaseIterableViaExtensionExcluded() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("ExtCaseIterable.swift")
        let swiftContent = """
        enum Planet {
            case mercury
            case venus
            case earth
        }

        extension Planet: CaseIterable {}

        let allPlanets = Planet.allCases
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        // CaseIterable conformance via extension should also exclude enum cases
        let unusedEnumCases = report.unused.filter { $0.type == .enumCase }
        #expect(unusedEnumCases.isEmpty)
    }

    @Test func testProtocolUsedAsTypeAnnotationNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("ProtocolAsType.swift")
        let swiftContent = """
        protocol Service {
            func execute()
        }

        func run(service: any Service) {
            service.execute()
        }
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedProtocols = report.unused.filter { $0.type == .protocol }
        #expect(!unusedProtocols.contains { $0.name == "Service" })
    }

    @Test func testCodingKeysEnumCasesNotFlagged() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testSwiftFile = tempDir.appendingPathComponent("CodingKeys.swift")
        let swiftContent = """
        struct User: Codable {
            let name: String
            let age: Int

            enum CodingKeys: String, CodingKey {
                case name
                case age
            }
        }

        let user = User(name: "Alice", age: 30)
        print(user.name)
        print(user.age)
        """

        try swiftContent.write(to: testSwiftFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions(
            includeOverrides: false,
            includeProtocols: false,
            includeObjc: false,
            showExcluded: false
        )

        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([testSwiftFile])

        let report = try ReportService.read(from: tempDir.path)

        // CodingKeys cases should not be flagged as unused enum cases
        let unusedEnumCases = report.unused.filter { $0.type == .enumCase }
        #expect(!unusedEnumCases.contains { $0.name == "name" })
        #expect(!unusedEnumCases.contains { $0.name == "age" })
    }

    @Test func testLargeDataset() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        var unusedItems: [ReportItem] = []
        for i in 1...100 {
            unusedItems.append(
                ReportItem(
                    id: i,
                    name: "function\(i)",
                    type: .function,
                    file: "/path/to/file\(i).swift",
                    line: i * 10,
                    exclusionReason: .none,
                    parentType: nil
                )
            )
        }

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        try ReportService.write(report: report, to: tempDir.path)
        let readReport = try ReportService.read(from: tempDir.path)

        #expect(readReport.unused.count == 100)

        for i in 1...100 {
            let entry = readReport.item(withId: i)
            #expect(entry != nil)
            #expect(entry?.name == "function\(i)")
            #expect(entry?.line == i * 10)
        }
    }

}
