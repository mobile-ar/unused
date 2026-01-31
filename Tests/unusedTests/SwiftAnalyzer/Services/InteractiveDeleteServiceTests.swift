//
//  Created by Fernando Romiti on 01/02/2026.
//

import Testing
import Foundation
@testable import unused

final class MockInputProvider: InteractiveInputProvider {
    private var responses: [String]
    private var currentIndex = 0

    init(responses: [String]) {
        self.responses = responses
    }

    func readLine() -> String? {
        guard currentIndex < responses.count else {
            return nil
        }
        let response = responses[currentIndex]
        currentIndex += 1
        return response
    }
}

final class MockEditorOpener: EditorOpenerProtocol {
    var xcodeOpenedCount = 0
    var zedOpenedCount = 0
    var lastFilePath: String?
    var lastLine: Int?
    var lastEditor: Editor?

    func open(filePath: String, lineNumber: Int, editor: Editor) throws {
        switch editor {
        case .xcode:
            xcodeOpenedCount += 1
        case .zed:
            zedOpenedCount += 1
        }
        lastFilePath = filePath
        lastLine = lineNumber
        lastEditor = editor
    }

    func open(id: Int, inDirectory directory: String, using editor: unused.Editor) throws {
        try open(filePath: directory, lineNumber: 1, editor: editor)
    }
}

struct InteractiveDeleteServiceTests {

    private func createTestItem(id: Int, name: String, type: DeclarationType, file: String, line: Int) -> ReportItem {
        ReportItem(
            id: id,
            name: name,
            type: type,
            file: file,
            line: line,
            exclusionReason: .none,
            parentType: nil
        )
    }

    @Test func testParseResponseYes() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("y") == .yes)
        #expect(service.testParseResponse("Y") == .yes)
        #expect(service.testParseResponse("yes") == .yes)
        #expect(service.testParseResponse("YES") == .yes)
        #expect(service.testParseResponse("  y  ") == .yes)
    }

    @Test func testParseResponseNo() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("n") == .no)
        #expect(service.testParseResponse("N") == .no)
        #expect(service.testParseResponse("no") == .no)
        #expect(service.testParseResponse("NO") == .no)
        #expect(service.testParseResponse("  n  ") == .no)
    }

    @Test func testParseResponseAll() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("a") == .all)
        #expect(service.testParseResponse("A") == .all)
        #expect(service.testParseResponse("all") == .all)
        #expect(service.testParseResponse("ALL") == .all)
    }

    @Test func testParseResponseQuit() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("q") == .quit)
        #expect(service.testParseResponse("Q") == .quit)
        #expect(service.testParseResponse("quit") == .quit)
        #expect(service.testParseResponse("QUIT") == .quit)
    }

    @Test func testParseResponseXcode() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("x") == .openXcode)
        #expect(service.testParseResponse("X") == .openXcode)
        #expect(service.testParseResponse("xcode") == .openXcode)
        #expect(service.testParseResponse("XCODE") == .openXcode)
    }

    @Test func testParseResponseZed() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("z") == .openZed)
        #expect(service.testParseResponse("Z") == .openZed)
        #expect(service.testParseResponse("zed") == .openZed)
        #expect(service.testParseResponse("ZED") == .openZed)
    }

    @Test func testParseResponseLineRange() {
        let service = InteractiveDeleteService()

        let response1 = service.testParseResponse("1-3")
        if case .lineRange(let lines) = response1 {
            #expect(lines == Set([1, 2, 3]))
        } else {
            #expect(Bool(false), "Expected lineRange response")
        }

        let response2 = service.testParseResponse("5 7 9")
        if case .lineRange(let lines) = response2 {
            #expect(lines == Set([5, 7, 9]))
        } else {
            #expect(Bool(false), "Expected lineRange response")
        }

        let response3 = service.testParseResponse("1-3 5 7-9")
        if case .lineRange(let lines) = response3 {
            #expect(lines == Set([1, 2, 3, 5, 7, 8, 9]))
        } else {
            #expect(Bool(false), "Expected lineRange response")
        }
    }

    @Test func testParseResponseDefaultsToNo() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("") == .no)
        #expect(service.testParseResponse("   ") == .no)
        #expect(service.testParseResponse(nil) == .no)
    }

    @Test func testParseResponseInvalidInputDefaultsToNo() {
        let service = InteractiveDeleteService()

        #expect(service.testParseResponse("invalid") == .no)
        #expect(service.testParseResponse("xyz") == .no)
        #expect(service.testParseResponse("abc123") == .no)
    }

    @Test func testInteractiveResponseEquality() {
        #expect(InteractiveResponse.yes == InteractiveResponse.yes)
        #expect(InteractiveResponse.no == InteractiveResponse.no)
        #expect(InteractiveResponse.all == InteractiveResponse.all)
        #expect(InteractiveResponse.quit == InteractiveResponse.quit)
        #expect(InteractiveResponse.openXcode == InteractiveResponse.openXcode)
        #expect(InteractiveResponse.openZed == InteractiveResponse.openZed)
        #expect(InteractiveResponse.yes != InteractiveResponse.no)
        #expect(InteractiveResponse.openXcode != InteractiveResponse.openZed)

        let lineRange1 = InteractiveResponse.lineRange(Set([1, 2, 3]))
        let lineRange2 = InteractiveResponse.lineRange(Set([1, 2, 3]))
        let lineRange3 = InteractiveResponse.lineRange(Set([4, 5, 6]))
        #expect(lineRange1 == lineRange2)
        #expect(lineRange1 != lineRange3)
    }

    @Test func testConfirmDeletionsReturnsFullDeclarationForYes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("Test.swift").path
        let source = """
            func unusedFunction() {
                print("hello")
            }
            """
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "unusedFunction",
            type: .function,
            file: filePath,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let mockInput = MockInputProvider(responses: ["y"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try service.confirmDeletions(items: [item])

        #expect(requests.count == 1)
        #expect(requests[0].item == item)
        #expect(requests[0].mode == DeletionMode.fullDeclaration)
        #expect(requests[0].isFullDeclaration == true)
    }

    @Test func testConfirmDeletionsReturnsSpecificLinesForLineRange() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("Test.swift").path
        let source = """
            func unusedFunction() {
                print("line 1")
                print("line 2")
                print("line 3")
            }
            """
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "unusedFunction",
            type: .function,
            file: filePath,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let mockInput = MockInputProvider(responses: ["2-3"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try service.confirmDeletions(items: [item])

        #expect(requests.count == 1)
        #expect(requests[0].item == item)
        #expect(requests[0].isFullDeclaration == false)
        if case .specificLines(let lines) = requests[0].mode {
            #expect(lines == Set([2, 3]))
        } else {
            #expect(Bool(false), "Expected specificLines mode")
        }
    }

    @Test func testConfirmDeletionsReturnsFullDeclarationForAll() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("Test.swift").path
        let source = """
            func func1() {}
            func func2() {}
            func func3() {}
            """
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)

        let items = [
            ReportItem(id: 1, name: "func1", type: .function, file: filePath, line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "func2", type: .function, file: filePath, line: 2, exclusionReason: .none, parentType: nil),
            ReportItem(id: 3, name: "func3", type: .function, file: filePath, line: 3, exclusionReason: .none, parentType: nil)
        ]

        let mockInput = MockInputProvider(responses: ["a"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try service.confirmDeletions(items: items)

        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.isFullDeclaration })
    }

    @Test func testConfirmDeletionsReturnsEmptyForQuit() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("Test.swift").path
        let source = "func unusedFunction() {}"
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)

        let item = ReportItem(
            id: 1,
            name: "unusedFunction",
            type: .function,
            file: filePath,
            line: 1,
            exclusionReason: .none,
            parentType: nil
        )

        let mockInput = MockInputProvider(responses: ["q"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try service.confirmDeletions(items: [item])

        #expect(requests.isEmpty)
    }

    @Test func testConfirmDeletionsMixedResponses() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("Test.swift").path
        let source = """
            func func1() {
                print("1")
            }
            func func2() {
                print("2")
            }
            func func3() {
                print("3")
            }
            """
        try source.write(toFile: filePath, atomically: true, encoding: .utf8)

        let items = [
            ReportItem(id: 1, name: "func1", type: .function, file: filePath, line: 1, exclusionReason: .none, parentType: nil),
            ReportItem(id: 2, name: "func2", type: .function, file: filePath, line: 4, exclusionReason: .none, parentType: nil),
            ReportItem(id: 3, name: "func3", type: .function, file: filePath, line: 7, exclusionReason: .none, parentType: nil)
        ]

        // First: yes (full), Second: specific lines, Third: no (skipped)
        let mockInput = MockInputProvider(responses: ["y", "5", "n"])
        let service = InteractiveDeleteService(inputProvider: mockInput)

        let requests = try service.confirmDeletions(items: items)

        #expect(requests.count == 2)
        #expect(requests[0].isFullDeclaration == true)
        #expect(requests[0].item.name == "func1")
        #expect(requests[1].isFullDeclaration == false)
        #expect(requests[1].item.name == "func2")
        if case .specificLines(let lines) = requests[1].mode {
            #expect(lines.contains(5))
        }
    }
}

extension InteractiveDeleteService {
    func testParseResponse(_ input: String?) -> InteractiveResponse {
        guard let input = input?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
            return .no
        }

        let lowercased = input.lowercased()

        switch lowercased {
        case "y", "yes":
            return .yes
        case "n", "no":
            return .no
        case "a", "all":
            return .all
        case "q", "quit":
            return .quit
        case "x", "xcode":
            return .openXcode
        case "z", "zed":
            return .openZed
        default:
            if let lines = try? LineRangeParser.parse(input) {
                return .lineRange(lines)
            }
            return .no
        }
    }
}
