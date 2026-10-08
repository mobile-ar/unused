import Foundation

struct AnalysisWarningPolicy: Sendable {
    var fileCountThreshold = 1_000
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    func directoryWarning(for directory: URL) -> String? {
        let path = directory.standardizedFileURL.resolvingSymlinksInPath().path
        if path == "/" {
            return "Warning: Analyzing the filesystem root '/'. This may scan an enormous number of files. Choose a project directory instead, or press Ctrl-C to stop."
        }
        let homePath = homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        if path == homePath {
            return "Warning: Analyzing your home directory '\(path)'. This may include unrelated projects and take substantial time and memory. Choose a project directory instead, or press Ctrl-C to stop."
        }
        return nil
    }

    func fileCountWarning(for count: Int, in directory: URL) -> String? {
        guard fileCountThreshold > 0, count >= fileCountThreshold else { return nil }
        let fileLabel = count == 1 ? "Swift file" : "Swift files"
        return "Warning: Discovered at least \(count) \(fileLabel) in '\(directory.path)' (warning threshold: \(fileCountThreshold)). Analysis may take substantial time and memory. Check the directory, press Ctrl-C to stop, or adjust --file-count-warning-threshold for intentionally large projects."
    }
}
