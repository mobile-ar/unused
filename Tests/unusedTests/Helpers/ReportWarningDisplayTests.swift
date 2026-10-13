import Testing

@testable import unused

struct ReportWarningDisplayTests {
    @Test(arguments: [false, true])
    func warningsStartWithOneBlankLineAndKeepTheirOrder(xcode: Bool) {
        let report = makeReport(warnings: ["First analysis warning", "Second analysis warning"])
        let output = lines(for: report, xcode: xcode)
        let expected = xcode
            ? ["warning: First analysis warning", "warning: Second analysis warning"]
            : ["Warning: First analysis warning".yellow, "Warning: Second analysis warning".yellow]

        #expect(Array(output.prefix(3)) == [""] + expected)
        #expect(output.filter { $0 == "" }.count == 1)
    }

    @Test(arguments: [false, true])
    func warningFreeReportsDoNotAddAWarningSeparator(xcode: Bool) {
        let output = lines(for: makeReport(), xcode: xcode)

        #expect(!output.contains(""))
        #expect(!output.contains { $0.contains("Warning:") || $0.hasPrefix("warning:") })
    }

    @Test(arguments: [false, true])
    func warningsAppearBeforeUnusedFindings(xcode: Bool) throws {
        let item = ReportItem(
            id: 1, name: "unusedHelper", type: .function, file: "/project/Source.swift",
            line: 12, exclusionReason: .none, parentType: nil
        )
        let output = lines(for: makeReport(warnings: ["Missing dependency metadata"], unused: [item]), xcode: xcode)
        let warningIndex = try #require(output.firstIndex { $0.contains("Missing dependency metadata") })
        let findingIndex = try #require(output.firstIndex { $0.contains("unusedHelper") })

        #expect(warningIndex == 1)
        #expect(warningIndex < findingIndex)
        if xcode {
            #expect(output[findingIndex] == "/project/Source.swift:12: warning: Unused function 'unusedHelper'")
            #expect(output.last == "warning: 1 unused declaration found")
        }
    }

    private func makeReport(warnings: [String] = [], unused: [ReportItem] = []) -> Report {
        Report(
            unused: unused,
            excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(), testFilesExcluded: 0, warnings: warnings
        )
    }

    private func lines(for report: Report, xcode: Bool) -> [String] {
        var output: [String] = []
        if xcode {
            XcodeFormatter.display(report: report, output: { output.append($0) })
        } else {
            ReportService.display(report: report, output: { output.append($0) })
        }
        return output
    }
}
