//
//  Created by Fernando Romiti on 07/12/2025.
//

import Testing
import Foundation
@testable import unused

struct OperatorUsageIntegrationTests {

    @Test
    func testEquatableOperatorsNotReportedAsUnused() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let summaryFile = tempDir.appendingPathComponent("Summary+Equatable.swift")
        let summaryContent = """
        import Foundation
        
        struct Summary {
            let count: Int
        }
        
        struct SummaryCategory {
            let type: String
        }
        
        extension Summary: @retroactive Equatable {
            public static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }
        
        extension SummaryCategory: @retroactive Equatable {
            public static func == (lhs: SummaryCategory, rhs: SummaryCategory) -> Bool {
                return lhs.type == rhs.type
            }
        }
        """
        try summaryContent.write(to: summaryFile, atomically: true, encoding: .utf8)
        
        let usageFile = tempDir.appendingPathComponent("Usage.swift")
        let usageContent = """
        import Foundation
        
        func compareSummaries() {
            let s1 = Summary(count: 10)
            let s2 = Summary(count: 10)
            
            if s1 == s2 {
                print("Equal summaries")
            }
            
            let c1 = SummaryCategory(type: "A")
            let c2 = SummaryCategory(type: "B")
            
            if c1 == c2 {
                print("Equal categories")
            }
        }
        """
        try usageContent.write(to: usageFile, atomically: true, encoding: .utf8)
        
        let analyzer = SwiftAnalyzer(
            options: AnalyzerOptions(
                includeOverrides: false,
                includeProtocols: false,
                includeObjc: false,
                showExcluded: false
            ),
            directory: tempDir.path
        )
        
        await analyzer.analyzeFiles([summaryFile, usageFile])
        
        let csvFile = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: csvFile.path))
        
        let csvContent = try String(contentsOf: csvFile, encoding: .utf8)
        let lines = csvContent.split(separator: "\n")
        
        let equalsOperators = lines.filter { $0.contains("==") }
        #expect(equalsOperators.isEmpty, "Equatable == operators should not be reported as unused when they are used")
    }
    
    @Test
    func testUserReportedIssueWithRetroactiveEquatable() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let summaryEquatableFile = tempDir.appendingPathComponent("Summary+Equatable.swift")
        let summaryEquatableContent = """
        import Foundation
        
        struct Summary {
            let count: Int
        }
        
        struct SummaryCategory {
            let type: String
        }
        
        extension Summary: @retroactive Equatable {
            public static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }
        
        extension SummaryCategory: @retroactive Equatable {
            public static func == (lhs: SummaryCategory, rhs: SummaryCategory) -> Bool {
                return lhs.type == rhs.type
            }
        }
        """
        try summaryEquatableContent.write(to: summaryEquatableFile, atomically: true, encoding: .utf8)
        
        let usageFile = tempDir.appendingPathComponent("Usage.swift")
        let usageContent = """
        import Foundation
        
        func testEquality() {
            let s1 = Summary(count: 5)
            let s2 = Summary(count: 5)
            let areEqual = s1 == s2
            
            let c1 = SummaryCategory(type: "TypeA")
            let c2 = SummaryCategory(type: "TypeB")
            let categoriesEqual = c1 == c2
            
            print(areEqual, categoriesEqual)
        }
        """
        try usageContent.write(to: usageFile, atomically: true, encoding: .utf8)
        
        let analyzer = SwiftAnalyzer(
            options: AnalyzerOptions(
                includeOverrides: false,
                includeProtocols: false,
                includeObjc: false,
                showExcluded: false
            ),
            directory: tempDir.path
        )
        
        await analyzer.analyzeFiles([summaryEquatableFile, usageFile])
        
        let csvFile = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: csvFile.path))
        
        let csvContent = try String(contentsOf: csvFile, encoding: .utf8)
        let lines = csvContent.split(separator: "\n")
        
        let summaryEqualsOperator = lines.filter { 
            $0.contains("==") && 
            $0.contains("Summary+Equatable.swift") && 
            $0.contains("10")
        }
        
        let categoryEqualsOperator = lines.filter { 
            $0.contains("==") && 
            $0.contains("Summary+Equatable.swift") && 
            $0.contains("18")
        }
        
        #expect(summaryEqualsOperator.isEmpty, "Summary == operator at line 10 should NOT be reported as unused")
        #expect(categoryEqualsOperator.isEmpty, "SummaryCategory == operator at line 18 should NOT be reported as unused")
    }
    
    @Test
    func testCustomOperatorsDetection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let operatorFile = tempDir.appendingPathComponent("CustomOperator.swift")
        let operatorContent = """
        import Foundation
        
        infix operator **: MultiplicationPrecedence
        
        func ** (lhs: Double, rhs: Double) -> Double {
            return pow(lhs, rhs)
        }
        
        func calculate() {
            let result = 2.0 ** 3.0
            print(result)
        }
        """
        try operatorContent.write(to: operatorFile, atomically: true, encoding: .utf8)
        
        let analyzer = SwiftAnalyzer(
            options: AnalyzerOptions(
                includeOverrides: false,
                includeProtocols: false,
                includeObjc: false,
                showExcluded: false
            ),
            directory: tempDir.path
        )
        
        await analyzer.analyzeFiles([operatorFile])
        
        let csvFile = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: csvFile.path))
        
        let csvContent = try String(contentsOf: csvFile, encoding: .utf8)
        let lines = csvContent.split(separator: "\n")
        
        let powerOperator = lines.filter { $0.contains("**") }
        #expect(powerOperator.isEmpty, "Custom ** operator should not be reported as unused when it is used")
    }
    
    @Test
    func testComparisonOperatorsUsage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let comparableFile = tempDir.appendingPathComponent("Comparable.swift")
        let comparableContent = """
        import Foundation
        
        struct Version {
            let major: Int
            let minor: Int
        }
        
        extension Version: Comparable {
            static func < (lhs: Version, rhs: Version) -> Bool {
                if lhs.major != rhs.major {
                    return lhs.major < rhs.major
                }
                return lhs.minor < rhs.minor
            }
            
            static func == (lhs: Version, rhs: Version) -> Bool {
                return lhs.major == rhs.major && lhs.minor == rhs.minor
            }
        }
        
        func compareVersions() {
            let v1 = Version(major: 1, minor: 0)
            let v2 = Version(major: 2, minor: 0)
            
            if v1 < v2 {
                print("v1 is older")
            }
            
            if v1 == v2 {
                print("same version")
            }
        }
        """
        try comparableContent.write(to: comparableFile, atomically: true, encoding: .utf8)

        let analyzer = SwiftAnalyzer(
            options: AnalyzerOptions(
                includeOverrides: false,
                includeProtocols: false,
                includeObjc: false,
                showExcluded: false
            ),
            directory: tempDir.path
        )

        await analyzer.analyzeFiles([comparableFile])

        let csvFile = tempDir.appendingPathComponent(".unused")
        #expect(FileManager.default.fileExists(atPath: csvFile.path))
        
        let csvContent = try String(contentsOf: csvFile, encoding: .utf8)
        let lines = csvContent.split(separator: "\n")
        
        let comparisonOperators = lines.filter { $0.contains("<") || $0.contains("==") }
        #expect(comparisonOperators.isEmpty, "Comparison operators should not be reported as unused when they are used")
    }

}
