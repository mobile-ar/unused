import Foundation
import Testing
@testable import unused

struct WriteOnlyReportMetadataTests {
    @Test(arguments: [ExclusionReason.none, .override, .protocolImplementation, .objcAttribute, .unresolvedProtocol, .unresolvedMacro])
    func metadataRoundTripsWithoutOverwritingSafeguards(_ reason: ExclusionReason) throws {
        let declaration = Declaration(name: "value", type: .variable, file: "/project/Subject.swift", line: 4,
            exclusionReason: reason, parentType: "Subject", isWriteOnly: true)
        let item = ReportItem(id: 1, declaration: declaration)
        #expect(item.isWriteOnly)
        #expect(item.declaration.isWriteOnly)
        #expect(item.exclusionReason == reason)
        #expect(item.declaration.exclusionReason == reason)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ReportItem.self, from: data)
        #expect(decoded == item)
        #expect(decoded.isWriteOnly)
        #expect(decoded.exclusionReason == reason)
    }

    @Test
    func unprotectedWriteOnlyFindingsCarryMetadata() {
        let declaration = Declaration(name: "value", type: .variable, file: "/project/Subject.swift", line: 4,
            exclusionReason: .writeOnly, parentType: "Subject")
        #expect(ReportItem(id: 1, declaration: declaration).isWriteOnly)
    }

    @Test
    func ordinaryFindingsAreNotWriteOnly() {
        let declaration = Declaration(name: "value", type: .variable, file: "/project/Subject.swift", line: 4,
            exclusionReason: .none, parentType: "Subject")
        let item = ReportItem(id: 1, declaration: declaration)
        #expect(!item.isWriteOnly)
        #expect(!item.declaration.isWriteOnly)
    }

    @Test(arguments: [ExclusionReason.override, .protocolImplementation, .objcAttribute])
    func displaysWriteOnlyFindingsSeparatelyWithoutLosingExclusionContext(_ reason: ExclusionReason) {
        let item = ReportItem(id: 1, name: "value", type: .variable, file: "/project/Subject.swift", line: 4,
            exclusionReason: reason, parentType: "Subject", isWriteOnly: true)
        let report = Report(unused: [item], excluded: ExcludedItems(overrides: [], protocolImplementations: [], objcItems: [], mainTypes: []),
            options: ReportOptions(), testFilesExcluded: 0)
        var output: [String] = []
        ReportService.display(report: report, output: { output.append($0) })
        #expect(output.contains { $0.contains("Write-Only Variables") })
        #expect(!output.contains { $0.contains("Unused Variables:") })
        #expect(output.contains { $0.contains("value") && $0.contains("[write-only]") && $0.contains("[\(reason.description)]") })
        var warnings: [String] = []
        XcodeFormatter.display(items: [item], output: { warnings.append($0) })
        #expect(warnings.contains { $0.contains("value") && $0.contains("[write-only]") })
    }
}
