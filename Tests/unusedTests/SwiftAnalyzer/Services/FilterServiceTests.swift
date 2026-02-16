//
//  Created by Fernando Romiti on 28/01/2026.
//

import Foundation
import Testing

@testable import unused

struct FilterServiceTests {

    private func createTestReport() -> Report {
        let unusedItems = [
            ReportItem(
                id: 1,
                name: "unusedFunction",
                type: .function,
                file: "/project/Sources/MyApp/Utils.swift",
                line: 10,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "unusedVariable",
                type: .variable,
                file: "/project/Sources/MyApp/Models/User.swift",
                line: 25,
                exclusionReason: .none,
                parentType: "User"
            ),
            ReportItem(
                id: 3,
                name: "UnusedClass",
                type: .class,
                file: "/project/Sources/MyApp/Services/Helper.swift",
                line: 5,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 4,
                name: "anotherFunction",
                type: .function,
                file: "/project/Sources/MyApp/Controllers/MainController.swift",
                line: 42,
                exclusionReason: .none,
                parentType: "MainController"
            ),
            ReportItem(
                id: 5,
                name: "helperMethod",
                type: .function,
                file: "/project/Sources/MyApp/Services/Helper.swift",
                line: 15,
                exclusionReason: .none,
                parentType: "Helper"
            )
        ]

        let excludedItems = ExcludedItems(
            overrides: [
                ReportItem(
                    id: 6,
                    name: "overrideMethod",
                    type: .function,
                    file: "/project/Sources/MyApp/Base.swift",
                    line: 20,
                    exclusionReason: .override,
                    parentType: "ChildClass"
                )
            ],
            protocolImplementations: [
                ReportItem(
                    id: 7,
                    name: "protocolMethod",
                    type: .function,
                    file: "/project/Sources/MyApp/Protocols.swift",
                    line: 30,
                    exclusionReason: .protocolImplementation,
                    parentType: "Implementation"
                )
            ],
            objcItems: [],
            mainTypes: []
        )

        return Report(
            unused: unusedItems,
            excluded: excludedItems,
            options: ReportOptions(),
            testFilesExcluded: 0
        )
    }

    @Test func testFilterByIds() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byIds: [1, 3])

        #expect(result.count == 2)
        #expect(result.contains { $0.id == 1 })
        #expect(result.contains { $0.id == 3 })
        #expect(!result.contains { $0.id == 2 })
    }

    @Test func testFilterBySingleId() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byIds: [2])

        #expect(result.count == 1)
        #expect(result.first?.name == "unusedVariable")
    }

    @Test func testFilterByNonExistentId() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byIds: [999])

        #expect(result.isEmpty)
    }

    @Test func testFilterByTypeFunction() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byTypes: [.function])

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.type == .function })
    }

    @Test func testFilterByTypeVariable() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byTypes: [.variable])

        #expect(result.count == 1)
        #expect(result.first?.name == "unusedVariable")
    }

    @Test func testFilterByTypeClass() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byTypes: [.class])

        #expect(result.count == 1)
        #expect(result.first?.name == "UnusedClass")
    }

    @Test func testFilterByMultipleTypes() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byTypes: [.function, .variable])

        #expect(result.count == 4)
    }

    @Test func testFilterByFilePatternExact() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byFilePattern: "Helper.swift")

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.file.contains("Helper.swift") })
    }

    @Test func testFilterByFilePatternGlob() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byFilePattern: "**/Services/**")

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.file.contains("/Services/") })
    }

    @Test func testFilterByFilePatternModels() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byFilePattern: "**/Models/**")

        #expect(result.count == 1)
        #expect(result.first?.name == "unusedVariable")
    }

    @Test func testFilterByNamePatternExact() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byNamePattern: "unusedFunction")

        #expect(result.count == 1)
        #expect(result.first?.name == "unusedFunction")
    }

    @Test func testFilterByNamePatternRegex() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byNamePattern: "^unused")

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.name.hasPrefix("unused") })
    }

    @Test func testFilterByNamePatternCaseInsensitive() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let result = filterService.filter(report: report, byNamePattern: "(?i)unused")

        #expect(result.count == 3)
    }

    @Test func testFilterByCombinedCriteria() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let criteria = FilterCriteria(
            types: [.function],
            filePattern: "**/Services/**"
        )

        let result = filterService.filter(report: report, criteria: criteria)

        #expect(result.count == 1)
        #expect(result.first?.name == "helperMethod")
    }

    @Test func testFilterWithEmptyCriteria() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let criteria = FilterCriteria()

        let result = filterService.filter(report: report, criteria: criteria)

        #expect(result.count == 5)
    }

    @Test func testFilterIncludesExcludedItems() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let criteria = FilterCriteria(includeExcluded: true)

        let result = filterService.filter(report: report, criteria: criteria)

        #expect(result.count == 7)
        #expect(result.contains { $0.exclusionReason == .override })
        #expect(result.contains { $0.exclusionReason == .protocolImplementation })
    }

    @Test func testFilterExcludedItemsById() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let criteria = FilterCriteria(ids: [6], includeExcluded: true)

        let result = filterService.filter(report: report, criteria: criteria)

        #expect(result.count == 1)
        #expect(result.first?.name == "overrideMethod")
        #expect(result.first?.exclusionReason == .override)
    }

    @Test func testSummary() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let summary = filterService.summary(report.unused)

        #expect(summary.functions == 3)
        #expect(summary.variables == 1)
        #expect(summary.classes == 1)
        #expect(summary.enumCases == 0)
        #expect(summary.protocols == 0)
        #expect(summary.typealiases == 0)
        #expect(summary.parameters == 0)
        #expect(summary.imports == 0)
    }

    @Test func testSummaryWithFilteredItems() async throws {
        let report = createTestReport()
        let filterService = FilterService()

        let filtered = filterService.filter(report: report, byTypes: [.function])
        let summary = filterService.summary(filtered)

        #expect(summary.functions == 3)
        #expect(summary.variables == 0)
        #expect(summary.classes == 0)
        #expect(summary.enumCases == 0)
        #expect(summary.protocols == 0)
        #expect(summary.typealiases == 0)
        #expect(summary.parameters == 0)
        #expect(summary.imports == 0)
    }

    @Test func testSummaryWithNewDeclarationTypes() async throws {
        let items = [
            ReportItem(
                id: 1,
                name: "MyAlias",
                type: .typealias,
                file: "/test/file.swift",
                line: 1,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 2,
                name: "AnotherAlias",
                type: .typealias,
                file: "/test/file.swift",
                line: 5,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 3,
                name: "unusedParam",
                type: .parameter,
                file: "/test/file.swift",
                line: 10,
                exclusionReason: .none,
                parentType: "MyClass.doWork"
            ),
            ReportItem(
                id: 4,
                name: "SomeModule",
                type: .import,
                file: "/test/file.swift",
                line: 1,
                exclusionReason: .none,
                parentType: nil
            ),
            ReportItem(
                id: 5,
                name: "unusedFunc",
                type: .function,
                file: "/test/file.swift",
                line: 20,
                exclusionReason: .none,
                parentType: nil
            )
        ]

        let filterService = FilterService()
        let summary = filterService.summary(items)

        #expect(summary.functions == 1)
        #expect(summary.variables == 0)
        #expect(summary.classes == 0)
        #expect(summary.enumCases == 0)
        #expect(summary.protocols == 0)
        #expect(summary.typealiases == 2)
        #expect(summary.parameters == 1)
        #expect(summary.imports == 1)
    }

    @Test func testFilterByTypeTypealias() async throws {
        let unusedItems = [
            ReportItem(id: 1, name: "MyAlias", type: .typealias, file: "/test.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "unusedFunc", type: .function, file: "/test.swift", line: 5, exclusionReason: .none, parentType: nil),
            ReportItem(id: 3, name: "AnotherAlias", type: .typealias, file: "/test.swift", line: 10, exclusionReason: .none, parentType: nil)
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let filterService = FilterService()
        let result = filterService.filter(report: report, byTypes: [.typealias])

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.type == .typealias })
    }

    @Test func testFilterByTypeParameter() async throws {
        let unusedItems = [
            ReportItem(id: 1, name: "param1", type: .parameter, file: "/test.swift", line: 1, exclusionReason: .none, parentType: "foo"),
            ReportItem(id: 2, name: "unusedFunc", type: .function, file: "/test.swift", line: 5, exclusionReason: .none, parentType: nil),
            ReportItem(id: 3, name: "param2", type: .parameter, file: "/test.swift", line: 10, exclusionReason: .none, parentType: "bar")
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let filterService = FilterService()
        let result = filterService.filter(report: report, byTypes: [.parameter])

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.type == .parameter })
    }

    @Test func testFilterByTypeImport() async throws {
        let unusedItems = [
            ReportItem(id: 1, name: "SomeModule", type: .import, file: "/test.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "unusedFunc", type: .function, file: "/test.swift", line: 5, exclusionReason: .none, parentType: nil)
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let filterService = FilterService()
        let result = filterService.filter(report: report, byTypes: [.import])

        #expect(result.count == 1)
        #expect(result.first?.type == .import)
        #expect(result.first?.name == "SomeModule")
    }

    @Test func testFilterByMultipleNewTypes() async throws {
        let unusedItems = [
            ReportItem(id: 1, name: "MyAlias", type: .typealias, file: "/test.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "param1", type: .parameter, file: "/test.swift", line: 5, exclusionReason: .none, parentType: "foo"),
            ReportItem(id: 3, name: "SomeModule", type: .import, file: "/test.swift", line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 4, name: "unusedFunc", type: .function, file: "/test.swift", line: 10, exclusionReason: .none, parentType: nil)
        ]

        let report = Report(
            unused: unusedItems,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(),
            testFilesExcluded: 0
        )

        let filterService = FilterService()
        let result = filterService.filter(report: report, byTypes: [.typealias, .parameter, .import])

        #expect(result.count == 3)
        #expect(!result.contains { $0.type == .function })
    }

    @Test func testFilterCriteriaIsEmpty() async throws {
        let emptyCriteria = FilterCriteria()
        #expect(emptyCriteria.isEmpty)

        let criteriaWithIds = FilterCriteria(ids: [1])
        #expect(!criteriaWithIds.isEmpty)

        let criteriaWithTypes = FilterCriteria(types: [.function])
        #expect(!criteriaWithTypes.isEmpty)

        let criteriaWithFile = FilterCriteria(filePattern: "*.swift")
        #expect(!criteriaWithFile.isEmpty)

        let criteriaWithName = FilterCriteria(namePattern: "test")
        #expect(!criteriaWithName.isEmpty)
    }

    @Test func testFilterCriteriaMatchesId() async throws {
        let criteria = FilterCriteria(ids: [1, 2, 3])

        let item1 = ReportItem(id: 1, name: "test", type: .function, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)
        let item5 = ReportItem(id: 5, name: "test", type: .function, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)

        #expect(criteria.matchesId(item1))
        #expect(!criteria.matchesId(item5))
    }

    @Test func testFilterCriteriaMatchesType() async throws {
        let criteria = FilterCriteria(types: [.function, .variable])

        let functionItem = ReportItem(id: 1, name: "test", type: .function, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)
        let classItem = ReportItem(id: 2, name: "test", type: .class, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)

        #expect(criteria.matchesType(functionItem))
        #expect(!criteria.matchesType(classItem))
    }

    @Test func testFilterCriteriaMatchesFilePattern() async throws {
        let criteria = FilterCriteria(filePattern: "**/Models/*.swift")

        let modelsItem = ReportItem(id: 1, name: "test", type: .function, file: "/project/Sources/Models/User.swift", line: 1, exclusionReason: .none, parentType: nil)
        let servicesItem = ReportItem(id: 2, name: "test", type: .function, file: "/project/Sources/Services/Api.swift", line: 1, exclusionReason: .none, parentType: nil)

        #expect(criteria.matchesFilePattern(modelsItem))
        #expect(!criteria.matchesFilePattern(servicesItem))
    }

    @Test func testFilterCriteriaMatchesNamePattern() async throws {
        let criteria = FilterCriteria(namePattern: "^unused")

        let matchingItem = ReportItem(id: 1, name: "unusedFunction", type: .function, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)
        let nonMatchingItem = ReportItem(id: 2, name: "helperFunction", type: .function, file: "test.swift", line: 1, exclusionReason: .none, parentType: nil)

        #expect(criteria.matchesNamePattern(matchingItem))
        #expect(!criteria.matchesNamePattern(nonMatchingItem))
    }

    @Test func testFilterCriteriaMatchesAllCriteria() async throws {
        let criteria = FilterCriteria(
            ids: [1, 2, 3],
            types: [.function],
            filePattern: "**/Services/**",
            namePattern: "helper"
        )

        let matchingItem = ReportItem(id: 1, name: "helperMethod", type: .function, file: "/project/Sources/Services/Helper.swift", line: 1, exclusionReason: .none, parentType: nil)
        let wrongId = ReportItem(id: 5, name: "helperMethod", type: .function, file: "/project/Sources/Services/Helper.swift", line: 1, exclusionReason: .none, parentType: nil)
        let wrongType = ReportItem(id: 1, name: "helperVar", type: .variable, file: "/project/Sources/Services/Helper.swift", line: 1, exclusionReason: .none, parentType: nil)
        let wrongFile = ReportItem(id: 1, name: "helperMethod", type: .function, file: "/project/Sources/Models/Helper.swift", line: 1, exclusionReason: .none, parentType: nil)
        let wrongName = ReportItem(id: 1, name: "utilityMethod", type: .function, file: "/project/Sources/Services/Helper.swift", line: 1, exclusionReason: .none, parentType: nil)

        #expect(criteria.matches(matchingItem))
        #expect(!criteria.matches(wrongId))
        #expect(!criteria.matches(wrongType))
        #expect(!criteria.matches(wrongFile))
        #expect(!criteria.matches(wrongName))
    }
}
