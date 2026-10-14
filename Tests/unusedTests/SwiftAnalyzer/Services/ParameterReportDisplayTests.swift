import Foundation
import Testing
@testable import unused

struct ParameterReportDisplayTests {
    private func report(items: [ReportItem]) -> Report {
        Report(
            unused: items,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(), testFilesExcluded: 0
        )
    }

    @Test
    func consoleNamesParameterFindingsAsLocalBindingsAndExplainsSignatureSafety() {
        let items = [
            ReportItem(
                id: 1, name: "value", type: .parameter, file: "/project/API.swift", line: 4,
                exclusionReason: .none, parentType: "process"
            ),
            ReportItem(
                id: 2, name: "extra", type: .parameter, file: "/project/Model.swift", line: 8,
                exclusionReason: .none, parentType: "Model.init"
            )
        ]
        var output: [String] = []
        ReportService.display(report: report(items: items), output: { output.append($0) })
        #expect(output.contains("\nUnused Local Parameter Bindings:".lavender.bold))
        #expect(output.contains {
            $0.contains("Signature removal is not proven safe")
                && $0.contains("Review bindings manually")
                && $0.contains("keep callable signatures unchanged")
        })
        #expect(output.contains { $0.contains("value") && $0.contains("process") && $0.contains("/project/API.swift") })
        #expect(output.contains { $0.contains("extra") && $0.contains("Model.init") && $0.contains("/project/Model.swift") })
        #expect(!output.contains { $0.contains("Unused Function Parameters:") })
        #expect(!output.contains { $0.contains("No unused code found") })
    }

    @Test
    func reportsWithoutParametersDoNotAddBindingWarnings() {
        let item = ReportItem(
            id: 1, name: "helper", type: .function, file: "/project/API.swift", line: 1,
            exclusionReason: .none, parentType: nil
        )
        var output: [String] = []
        ReportService.display(report: report(items: [item]), output: { output.append($0) })
        #expect(output.contains { $0.contains("Unused Functions:") })
        #expect(output.contains { $0.contains("helper") })
        #expect(!output.contains { $0.contains("Parameter Bindings") || $0.contains("Signature removal") })
    }

    @Test
    func bindingReportsKeepTheirParameterCategoryAndIdentityWhenPersisted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identity = DeclarationIdentity(
            file: "/project/API.swift", offset: 20,
            signature: MemberSignature(kind: .parameter, name: "value", resultType: "Int"),
            moduleName: "App", lexicalScope: [0], isTypeMember: false
        )
        let item = ReportItem(
            id: 1, name: "value", type: .parameter, file: identity.file, line: 4,
            exclusionReason: .none, parentType: "process", identity: identity
        )
        try ReportService.write(report: report(items: [item]), to: directory.path)
        let persisted = try ReportService.read(from: directory.path)
        #expect(persisted.unused == [item])
        #expect(persisted.unused.first?.type == .parameter)
        #expect(persisted.unused.first?.identity == identity)

        var output: [String] = []
        ReportService.display(report: persisted, output: { output.append($0) })
        #expect(output.contains { $0.contains("Unused Local Parameter Bindings:") })
        #expect(output.contains { $0.contains("Signature removal is not proven safe") })
    }
}
