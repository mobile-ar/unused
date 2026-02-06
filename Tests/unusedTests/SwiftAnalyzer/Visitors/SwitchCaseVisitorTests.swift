//
//  Created by Fernando Romiti on 02/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct SwitchCaseVisitorTests {

    @Test func testFindsSwitchCaseWithDotSyntax() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            case .inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].enumCaseName == "active")
        #expect(visitor.switchCases[0].sourceText.contains("case .active"))
    }

    @Test func testFindsSwitchCaseWithFullTypeName() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case Status.active:
                print("Active")
            case Status.inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].enumCaseName == "active")
    }

    @Test func testFindsSwitchCaseWithAssociatedValue() {
        let source = """
        enum Result {
            case success(String)
            case failure(Error)
        }
        
        func handle(result: Result) {
            switch result {
            case .success(let message):
                print(message)
            case .failure(let error):
                print(error)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Result",
            enumCaseName: "success",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].enumCaseName == "success")
    }

    @Test func testIgnoresOtherCases() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            case .inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].enumCaseName == "active")
    }

    @Test func testFindsMultipleSwitchStatements() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle1(status: Status) {
            switch status {
            case .active:
                print("Active")
            case .inactive:
                print("Inactive")
            }
        }
        
        func handle2(status: Status) {
            switch status {
            case .active:
                print("Active again")
            case .inactive:
                print("Inactive again")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 2)
    }

    @Test func testNoMatchesForNonexistentCase() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            case .inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "pending",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.isEmpty)
    }

    @Test func testLineRangeIsCorrect() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            case .inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].lineRange.lowerBound == 8)
    }

    @Test func testFilePath() {
        let source = """
        enum Status {
            case active
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            default:
                break
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "/path/to/file.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].filePath == "/path/to/file.swift")
    }

    @Test func testFindsCaseWithMultiplePatterns() {
        let source = """
        enum Status {
            case active
            case pending
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active, .pending:
                print("In progress")
            case .inactive:
                print("Inactive")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "active",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
    }

    @Test func testFindsCaseWithLetBinding() {
        let source = """
        enum Result<T> {
            case success(T)
            case failure(Error)
        }
        
        func handle(result: Result<String>) {
            switch result {
            case let .success(value):
                print(value)
            case let .failure(error):
                print(error)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Result",
            enumCaseName: "success",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
        #expect(visitor.switchCases[0].enumCaseName == "success")
    }

    @Test func testIgnoresDefaultCase() {
        let source = """
        enum Status {
            case active
            case inactive
        }
        
        func handle(status: Status) {
            switch status {
            case .active:
                print("Active")
            default:
                print("Other")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Status",
            enumCaseName: "inactive",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.isEmpty)
    }

    @Test func testNestedSwitch() {
        let source = """
        enum Outer {
            case a
            case b
        }
        
        enum Inner {
            case x
            case y
        }
        
        func handle(outer: Outer, inner: Inner) {
            switch outer {
            case .a:
                switch inner {
                case .x:
                    print("a-x")
                case .y:
                    print("a-y")
                }
            case .b:
                print("b")
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = SwitchCaseVisitor(
            enumTypeName: "Inner",
            enumCaseName: "x",
            filePath: "test.swift",
            sourceFile: sourceFile
        )
        visitor.walk(sourceFile)

        #expect(visitor.switchCases.count == 1)
    }
}