import Testing
@testable import unused

struct XcodeFormatterParameterTests {
    private func parameter() -> ReportItem {
        ReportItem(
            id: 1, name: "value", type: .parameter, file: "/project/API.swift", line: 12,
            exclusionReason: .none, parentType: "process"
        )
    }

    @Test
    func reportDiagnosticsDescribeBindingsWithoutPromisingSafeSignatureRemoval() {
        let report = Report(
            unused: [parameter()],
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(), testFilesExcluded: 0
        )
        var output: [String] = []
        XcodeFormatter.display(report: report, output: { output.append($0) })
        #expect(output == [
            "/project/API.swift:12: warning: Unused local parameter binding 'value' in process; "
                + "signature removal is not proven safe; manual review required; keep signature unchanged",
            "warning: 1 unused declaration found"
        ])
    }

    @Test
    func itemDiagnosticsUseTheSameBindingOnlyWording() {
        var output: [String] = []
        XcodeFormatter.display(items: [parameter()], output: { output.append($0) })
        #expect(output == [
            "/project/API.swift:12: warning: Unused local parameter binding 'value' in process; "
                + "signature removal is not proven safe; manual review required; keep signature unchanged",
            "warning: 1 unused declaration found"
        ])
    }

    @Test
    func nonParameterDiagnosticsKeepTheirExistingMessages() {
        let item = ReportItem(
            id: 2, name: "helper", type: .function, file: "/project/API.swift", line: 2,
            exclusionReason: .none, parentType: nil
        )
        var output: [String] = []
        XcodeFormatter.display(items: [item], output: { output.append($0) })
        #expect(output == [
            "/project/API.swift:2: warning: Unused function 'helper'",
            "warning: 1 unused declaration found"
        ])
    }
}
