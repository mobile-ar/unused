//
//  Created by Fernando Romiti on 02/02/2026.
//

import Testing
import SwiftParser
import SwiftSyntax
@testable import unused

struct InitAssignmentVisitorTests {

    @Test func testFindsSimpleSelfAssignment() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].propertyName == "name")
        #expect(visitor.assignments[0].assignedFromParameter == "name")
        #expect(visitor.assignments[0].sourceText.contains("self.name = name"))
    }

    @Test func testFindsAssignmentWithDifferentParameterName() {
        let source = """
        struct User {
            let name: String
            
            init(userName: String) {
                self.name = userName
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].propertyName == "name")
        #expect(visitor.assignments[0].assignedFromParameter == "userName")
    }

    @Test func testFindsAssignmentWithExpression() {
        let source = """
        struct Report {
            let generatedAt: Date
            
            init() {
                self.generatedAt = Date()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "generatedAt",
            typeName: "Report",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].propertyName == "generatedAt")
        #expect(visitor.assignments[0].assignedFromParameter == nil)
        #expect(visitor.assignments[0].sourceText.contains("self.generatedAt = Date()"))
    }

    @Test func testFindsMultipleInits() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
            
            init() {
                self.name = "Default"
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 2)
    }

    @Test func testIgnoresOtherProperties() {
        let source = """
        struct User {
            let name: String
            let age: Int
            
            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].propertyName == "name")
    }

    @Test func testTracksParameterUsedOnlyForAssignment() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.initParameters["name"] != nil)
        #expect(visitor.initParameters["name"]?.usedOnlyForPropertyAssignment == true)
    }

    @Test func testParameterUsedMultipleTimes() {
        let source = """
        struct User {
            let name: String
            let displayName: String
            
            init(name: String) {
                self.name = name
                self.displayName = name.uppercased()
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.initParameters["name"] != nil)
        #expect(visitor.initParameters["name"]?.usedOnlyForPropertyAssignment == false)
    }

    @Test func testFindsAssignmentInClass() {
        let source = """
        class ViewModel {
            let title: String
            
            init(title: String) {
                self.title = title
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "title",
            typeName: "ViewModel",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].propertyName == "title")
    }

    @Test func testFindsAssignmentInExtension() {
        let source = """
        struct User {
            let name: String
        }
        
        extension User {
            init(fullName: String) {
                self.name = fullName
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].assignedFromParameter == "fullName")
    }

    @Test func testIgnoresOtherTypes() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        
        struct Admin {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
    }

    @Test func testFindsAssignmentWithSecondParameterName() {
        let source = """
        struct Config {
            let value: Int
            
            init(with value: Int) {
                self.value = value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "value",
            typeName: "Config",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].assignedFromParameter == "value")
    }

    @Test func testNoAssignmentsForNonexistentProperty() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "nonexistent",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.isEmpty)
    }

    @Test func testLineRangeIsCorrect() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].lineRange == 5...5)
    }

    @Test func testFindAssignmentWithComplexExpression() {
        let source = """
        struct Config {
            let timeout: TimeInterval
            
            init(timeoutSeconds: Int) {
                self.timeout = TimeInterval(timeoutSeconds)
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "timeout",
            typeName: "Config",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].assignedFromParameter == nil)
    }

    @Test func testFindsAssignmentInActor() {
        let source = """
        actor DataStore {
            let identifier: String
            
            init(identifier: String) {
                self.identifier = identifier
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "identifier",
            typeName: "DataStore",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
        #expect(visitor.assignments[0].assignedFromParameter == "identifier")
    }

    @Test func testFindsAssignmentInEnum() {
        let source = """
        enum Result {
            case success(String)
            case failure(Error)
            
            var message: String = ""
            
            init(message: String) {
                self = .success(message)
                self.message = message
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "message",
            typeName: "Result",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        #expect(visitor.assignments.count == 1)
    }

    @Test func testTracksParameterColumnPositions() {
        let source = """
        struct User {
            let name: String
            
            init(name: String) {
                self.name = name
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        let paramInfo = visitor.initParameters["name"]
        #expect(paramInfo != nil)
        #expect(paramInfo?.startColumn == 10)
        #expect(paramInfo?.endColumn == 22)
    }

    @Test func testTracksFirstParameterDeletionRange() {
        let source = """
        struct User {
            let name: String
            let age: Int
            
            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "name",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        let nameParam = visitor.initParameters["name"]
        #expect(nameParam != nil)
        #expect(nameParam?.isFirstParameter == true)
        #expect(nameParam?.isLastParameter == false)
        #expect(nameParam?.hasTrailingComma == true)
        // Deletion should include the trailing comma
        #expect(nameParam?.deletionEndColumn ?? 0 > nameParam?.endColumn ?? 0)
    }

    @Test func testTracksLastParameterDeletionRange() {
        let source = """
        struct User {
            let name: String
            let age: Int
            
            init(name: String, age: Int) {
                self.name = name
                self.age = age
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "age",
            typeName: "User",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        let ageParam = visitor.initParameters["age"]
        #expect(ageParam != nil)
        #expect(ageParam?.isFirstParameter == false)
        #expect(ageParam?.isLastParameter == true)
        #expect(ageParam?.hasTrailingComma == false)
        // Deletion should include the preceding comma
        #expect(ageParam?.deletionStartColumn ?? 0 < ageParam?.startColumn ?? 0)
    }

    @Test func testTracksMiddleParameterDeletionRange() {
        let source = """
        struct Config {
            let a: Int
            let b: Int
            let c: Int
            
            init(a: Int, b: Int, c: Int) {
                self.a = a
                self.b = b
                self.c = c
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "b",
            typeName: "Config",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        let bParam = visitor.initParameters["b"]
        #expect(bParam != nil)
        #expect(bParam?.isFirstParameter == false)
        #expect(bParam?.isLastParameter == false)
        #expect(bParam?.hasTrailingComma == true)
        // Middle parameter with trailing comma - deletion includes comma
        #expect(bParam?.deletionEndColumn ?? 0 > bParam?.endColumn ?? 0)
    }

    @Test func testTracksSingleParameterDeletionRange() {
        let source = """
        struct Simple {
            let value: Int
            
            init(value: Int) {
                self.value = value
            }
        }
        """

        let sourceFile = Parser.parse(source: source)
        let visitor = InitAssignmentVisitor(
            propertyName: "value",
            typeName: "Simple",
            sourceFile: sourceFile,
            fileName: "test.swift"
        )
        visitor.walk(sourceFile)

        let valueParam = visitor.initParameters["value"]
        #expect(valueParam != nil)
        #expect(valueParam?.isFirstParameter == true)
        #expect(valueParam?.isLastParameter == true)
        #expect(valueParam?.hasTrailingComma == false)
        // Single parameter - deletion range matches parameter range
        #expect(valueParam?.deletionStartColumn == valueParam?.startColumn)
        #expect(valueParam?.deletionEndColumn == valueParam?.endColumn)
    }
}