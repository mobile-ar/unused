import Testing

@testable import unused

struct ReportWarningDisplayTests {
    @Test(arguments: [false, true])
    func analysisWarningsAreNotDisplayed(xcode: Bool) {
        let report = makeReport(warnings: [
            "Cannot resolve inherited type or protocol 'SyntaxVisitor' for 'WriteOnlyVariableVisitor'. Potentially required members are excluded from unused results to avoid false positives.",
            "Unsupported attached macro @Argument at /project/Analyze.swift:14; cannot resolve expansion dependencies for attached declaration and possible direct members."
        ])
        let output = lines(for: report, xcode: xcode)

        #expect(output == lines(for: makeReport(), xcode: xcode))
        #expect(!output.contains(""))
        #expect(!output.contains { $0.contains("Warning:") || $0.hasPrefix("warning:") })
    }

    @Test(arguments: [false, true])
    func warningFreeReportsDoNotAddAWarningSeparator(xcode: Bool) {
        let output = lines(for: makeReport(), xcode: xcode)

        #expect(!output.contains(""))
        #expect(!output.contains { $0.contains("Warning:") || $0.hasPrefix("warning:") })
    }

    @Test(arguments: [false, true])
    func analysisWarningsDoNotAffectUnusedFindings(xcode: Bool) throws {
        let item = ReportItem(
            id: 1, name: "unusedHelper", type: .function, file: "/project/Source.swift",
            line: 12, exclusionReason: .none, parentType: nil
        )
        let output = lines(for: makeReport(warnings: ["Missing dependency metadata"], unused: [item]), xcode: xcode)
        let findingIndex = try #require(output.firstIndex { $0.contains("unusedHelper") })

        #expect(output == lines(for: makeReport(unused: [item]), xcode: xcode))
        #expect(!output.contains { $0.contains("Missing dependency metadata") })
        #expect(!output.contains(""))
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
