import ArgumentParser
import Darwin
import Foundation

struct Graph: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Explore incoming references and outgoing dependencies for a report declaration"
    )

    @Argument(help: "The declaration ID from the analysis report")
    var id: Int

    @Argument(help: "The directory containing .unused.json (defaults to the current directory)")
    var directory: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Display only incoming references; summary still includes both directions")
    var inboundOnly = false

    @Flag(name: .long, help: "Display only outgoing dependencies; summary still includes both directions")
    var outboundOnly = false

    @Option(name: .long, help: "Number of reference levels to display (1-10)")
    var depth = 1

    @Option(name: .long, help: "Maximum nodes displayed per branch (1-1000); counts remain complete")
    var limit = 20

    @Option(name: .long, help: "Output width in columns (20-300); defaults to the terminal width")
    var width: Int?

    @Flag(name: .long, help: "Include tests even if they were excluded from the report's analysis")
    var includeTests = false

    @Flag(name: .long, help: "Use ASCII boxes, connectors and status indicators")
    var ascii = false

    @Flag(name: .long, help: "Disable ANSI colors and progress animation")
    var noColor = false

    mutating func validate() throws {
        guard id > 0 else { throw ValidationError("Declaration IDs must be positive.") }
        guard !(inboundOnly && outboundOnly) else {
            throw ValidationError("Choose either --inbound-only or --outbound-only, not both.")
        }
        guard (1...10).contains(depth) else { throw ValidationError("--depth must be between 1 and 10.") }
        guard (1...1000).contains(limit) else { throw ValidationError("--limit must be between 1 and 1000.") }
        if let width, !(20...300).contains(width) {
            throw ValidationError("--width must be between 20 and 300.")
        }
    }

    func run() async throws {
        guard ReportService.reportExists(in: directory) else {
            throw ValidationError("No .unused.json found in \(directory). Run 'unused analyze' first.")
        }
        let report = try ReportService.read(from: directory)
        guard let item = report.item(withId: id) else {
            throw ValidationError("No declaration with ID \(id) in this report. Use 'unused analyze' to view the available IDs.")
        }
        guard item.type != .parameter && item.type != .import else {
            throw ValidationError("A \(item.type.rawValue) finding has no independent call graph. Select its enclosing declaration instead.")
        }

        let spinner = ConsoleSpinner()
        if !noColor { await spinner.start(message: "Collecting project references...") }
        let service = ReferenceGraphService()
        var result = await service.buildGraph(for: item, in: directory, includeTests: includeTests || report.options.includeTests)
        if !noColor { await spinner.stop(success: result.targetFound) }

        let fileURL = item.file.hasPrefix("/")
            ? URL(fileURLWithPath: item.file)
            : URL(fileURLWithPath: directory).appendingPathComponent(item.file)
        // Report timestamps are serialized to whole seconds, unlike filesystem modification dates.
        if let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           modified.timeIntervalSince(report.generatedAt) >= 1 {
            result.warnings.append("Source changed since the report was generated. The graph uses current sources; run 'unused analyze' to refresh findings and IDs.")
        }
        let options = GraphDisplayOptions(
            inboundOnly: inboundOnly, outboundOnly: outboundOnly, depth: depth, limit: limit,
            width: width ?? terminalWidth, ascii: ascii, color: !noColor && OutputConfig.colorEnabled, directory: directory
        )
        print(GraphRenderer().render(result, options: options))
    }

    private var terminalWidth: Int {
        var size = winsize()
        if isatty(STDOUT_FILENO) != 0, ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return max(20, min(300, Int(size.ws_col)))
        }
        return 100
    }
}
