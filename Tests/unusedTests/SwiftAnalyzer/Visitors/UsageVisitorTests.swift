//
//  Created by Fernando Romiti on 07/12/2025.
//

import Testing
import SwiftSyntax
import SwiftParser
@testable import unused

struct UsageVisitorTests {
    
    @Test
    func testInfixOperatorDetection() throws {
        let source = """
        func compare(a: Int, b: Int) -> Bool {
            return a == b
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("=="))
    }
    
    @Test
    func testMultipleInfixOperators() throws {
        let source = """
        func calculate(a: Int, b: Int, c: Int) -> Int {
            return a + b * c - 10
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("+"))
        #expect(visitor.usedIdentifiers.contains("*"))
        #expect(visitor.usedIdentifiers.contains("-"))
    }
    
    @Test
    func testEquatableOperatorUsage() throws {
        let source = """
        struct Summary {
            let count: Int
        }
        
        extension Summary: Equatable {
            static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }
        
        func test() {
            let s1 = Summary(count: 5)
            let s2 = Summary(count: 5)
            let result = s1 == s2
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("=="))
    }
    
    @Test
    func testPrefixOperatorDetection() throws {
        let source = """
        func negate(value: Bool) -> Bool {
            return !value
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("!"))
    }
    
    @Test
    func testPostfixOperatorDetection() throws {
        let source = """
        postfix operator ++
        
        postfix func ++ (value: inout Int) -> Int {
            value += 1
            return value
        }
        
        func increment() {
            var x = 5
            x++
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("++"))
    }
    
    @Test
    func testComparisonOperators() throws {
        let source = """
        func compare(a: Int, b: Int) {
            let eq = a == b
            let neq = a != b
            let lt = a < b
            let lte = a <= b
            let gt = a > b
            let gte = a >= b
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("=="))
        #expect(visitor.usedIdentifiers.contains("!="))
        #expect(visitor.usedIdentifiers.contains("<"))
        #expect(visitor.usedIdentifiers.contains("<="))
        #expect(visitor.usedIdentifiers.contains(">"))
        #expect(visitor.usedIdentifiers.contains(">="))
    }
    
    @Test
    func testLogicalOperators() throws {
        let source = """
        func logic(a: Bool, b: Bool) -> Bool {
            return a && b || !a
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("&&"))
        #expect(visitor.usedIdentifiers.contains("||"))
        #expect(visitor.usedIdentifiers.contains("!"))
    }
    
    @Test
    func testCustomOperator() throws {
        let source = """
        infix operator **: MultiplicationPrecedence
        
        func ** (lhs: Double, rhs: Double) -> Double {
            return pow(lhs, rhs)
        }
        
        func calculate() {
            let result = 2.0 ** 3.0
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("**"))
    }
    
    @Test
    func testRetroactiveEquatableConformance() throws {
        let source = """
        struct Summary {
            let count: Int
        }
        
        extension Summary: @retroactive Equatable {
            public static func == (lhs: Summary, rhs: Summary) -> Bool {
                return lhs.count == rhs.count
            }
        }
        
        struct SummaryCategory {
            let type: String
        }
        
        extension SummaryCategory: @retroactive Equatable {
            public static func == (lhs: SummaryCategory, rhs: SummaryCategory) -> Bool {
                return lhs.type == rhs.type
            }
        }
        
        func test() {
            let s1 = Summary(count: 1)
            let s2 = Summary(count: 1)
            let c1 = SummaryCategory(type: "A")
            let c2 = SummaryCategory(type: "A")
            
            if s1 == s2 && c1 == c2 {
                print("Equal")
            }
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("=="))
    }
    
    @Test
    func testFunctionReferences() throws {
        let source = """
        func myFunction() {
            print("Hello")
        }
        
        func caller() {
            myFunction()
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("myFunction"))
    }
    
    @Test
    func testMemberAccess() throws {
        let source = """
        struct User {
            let name: String
        }
        
        func test() {
            let user = User(name: "John")
            print(user.name)
        }
        """
        
        let sourceFile = Parser.parse(source: source)
        let visitor = UsageVisitor()
        visitor.walk(sourceFile)
        
        #expect(visitor.usedIdentifiers.contains("name"))
    }
}
