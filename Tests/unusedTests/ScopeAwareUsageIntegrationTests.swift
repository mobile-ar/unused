//
//  Created by Fernando Romiti on 14/02/2026.
//

import Testing
import Foundation
@testable import unused

struct ScopeAwareUsageIntegrationTests {

    @Test
    func testSameMethodNameDifferentTypes_onlyOneUsedViaTypedVariable() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            func process() {
                print("logging")
            }
        }

        class Validator {
            func process() {
                print("validating")
            }
        }

        func main() {
            let logger: Logger = Logger()
            logger.process()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)

        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let validatorProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Validator" }
        #expect(validatorProcessUnused, "Validator.process() should be detected as unused")

        let loggerProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Logger" }
        #expect(!loggerProcessUnused, "Logger.process() should NOT be detected as unused")
    }

    @Test
    func testSameMethodNameBothUsedViaTypedVariables() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            func process() {
                print("logging")
            }
        }

        class Validator {
            func process() {
                print("validating")
            }
        }

        func main() {
            let logger: Logger = Logger()
            logger.process()
            let validator: Validator = Validator()
            validator.process()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let loggerProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Logger" }
        #expect(!loggerProcessUnused, "Logger.process() should be used")

        let validatorProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Validator" }
        #expect(!validatorProcessUnused, "Validator.process() should be used")
    }

    @Test
    func testSameMethodNameUsedViaUntypedVariable_conservativelyMarkedUsed() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            func process() {
                print("logging")
            }
        }

        class Validator {
            func process() {
                print("validating")
            }
        }

        func getWorker() -> Logger { Logger() }

        func main() {
            let worker = getWorker()
            worker.process()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let loggerProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Logger" }
        #expect(!loggerProcessUnused, "Logger.process() should be conservatively marked as used (untyped variable)")

        let validatorProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Validator" }
        #expect(!validatorProcessUnused, "Validator.process() should be conservatively marked as used (untyped variable)")
    }

    @Test
    func testSameMethodNameUsedViaSelf() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            func process() {
                print("logging")
            }
            func run() {
                self.process()
            }
        }

        class Validator {
            func process() {
                print("validating")
            }
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let loggerProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Logger" }
        #expect(!loggerProcessUnused, "Logger.process() is used via self.process()")

        let validatorProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Validator" }
        #expect(validatorProcessUnused, "Validator.process() should be detected as unused")
    }

    @Test
    func testSameMethodNameUsedViaBareCall() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            func process() {
                print("logging")
            }
            func run() {
                process()
            }
        }

        class Validator {
            func process() {
                print("validating")
            }
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let loggerProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Logger" }
        #expect(!loggerProcessUnused, "Logger.process() is called via bare call process()")

        let validatorProcessUnused = unusedWithParent.contains { $0.0 == "process" && $0.1 == "Validator" }
        #expect(!validatorProcessUnused, "Validator.process() conservatively marked used since bare call exists")
    }

    @Test
    func testStaticMethodQualifiedUsage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Logger {
            static func configure() {
                print("configuring logger")
            }
        }

        class Validator {
            static func configure() {
                print("configuring validator")
            }
        }

        func main() {
            Logger.configure()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let loggerConfigureUnused = unusedWithParent.contains { $0.0 == "configure" && $0.1 == "Logger" }
        #expect(!loggerConfigureUnused, "Logger.configure() should be used via static call")

        let validatorConfigureUnused = unusedWithParent.contains { $0.0 == "configure" && $0.1 == "Validator" }
        #expect(validatorConfigureUnused, "Validator.configure() should be detected as unused")
    }

    @Test
    func testSamePropertyNameDifferentTypes() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class UserProfile {
            var displayName: String = "user"
        }

        class CompanyProfile {
            var displayName: String = "company"
        }

        func main() {
            let user: UserProfile = UserProfile()
            print(user.displayName)
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let userDisplayNameUnused = unusedWithParent.contains { $0.0 == "displayName" && $0.1 == "UserProfile" }
        #expect(!userDisplayNameUnused, "UserProfile.displayName should be used")

        let companyDisplayNameUnused = unusedWithParent.contains { $0.0 == "displayName" && $0.1 == "CompanyProfile" }
        #expect(companyDisplayNameUnused, "CompanyProfile.displayName should be detected as unused")
    }

    @Test
    func testMultipleFilesQualifiedUsage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let declarationFile = tempDir.appendingPathComponent("Types.swift")
        let declarationContent = """
        class NetworkClient {
            func fetch() {
                print("fetching")
            }
        }

        class DatabaseClient {
            func fetch() {
                print("querying")
            }
        }
        """

        let usageFile = tempDir.appendingPathComponent("Usage.swift")
        let usageContent = """
        func loadData() {
            let client: NetworkClient = NetworkClient()
            client.fetch()
        }
        """

        try declarationContent.write(to: declarationFile, atomically: true, encoding: .utf8)
        try usageContent.write(to: usageFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([declarationFile, usageFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let networkFetchUnused = unusedWithParent.contains { $0.0 == "fetch" && $0.1 == "NetworkClient" }
        #expect(!networkFetchUnused, "NetworkClient.fetch() should be used")

        let dbFetchUnused = unusedWithParent.contains { $0.0 == "fetch" && $0.1 == "DatabaseClient" }
        #expect(dbFetchUnused, "DatabaseClient.fetch() should be detected as unused")
    }

    @Test
    func testOptionalChainingQualifiedUsage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class ServiceA {
            func execute() {}
        }

        class ServiceB {
            func execute() {}
        }

        func test() {
            let a: ServiceA? = ServiceA()
            a?.execute()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let serviceAExecuteUnused = unusedWithParent.contains { $0.0 == "execute" && $0.1 == "ServiceA" }
        #expect(!serviceAExecuteUnused, "ServiceA.execute() used via optional chaining")

        let serviceBExecuteUnused = unusedWithParent.contains { $0.0 == "execute" && $0.1 == "ServiceB" }
        #expect(serviceBExecuteUnused, "ServiceB.execute() should be detected as unused")
    }

    @Test
    func testConstructorInferenceQualifiedUsage() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let sourceFile = tempDir.appendingPathComponent("Models.swift")
        let sourceContent = """
        class Encoder {
            func encode() {}
        }

        class Decoder {
            func encode() {}
        }

        func test() {
            let enc = Encoder()
            enc.encode()
        }
        """

        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let options = AnalyzerOptions()
        let analyzer = SwiftAnalyzer(options: options, directory: tempDir.path)
        await analyzer.analyzeFiles([sourceFile])

        let report = try ReportService.read(from: tempDir.path)
        let unusedWithParent = report.unused.map { ($0.name, $0.parentType) }

        let encoderEncodeUnused = unusedWithParent.contains { $0.0 == "encode" && $0.1 == "Encoder" }
        #expect(!encoderEncodeUnused, "Encoder.encode() should be used via constructor-inferred type")

        let decoderEncodeUnused = unusedWithParent.contains { $0.0 == "encode" && $0.1 == "Decoder" }
        #expect(decoderEncodeUnused, "Decoder.encode() should be detected as unused")
    }

}
