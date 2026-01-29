//
//  Created by Fernando Romiti on 28/01/2026.
//

struct FilterCriteria {
    let ids: [Int]?
    let types: [DeclarationType]?
    /// Filter by file path pattern (glob pattern, e.g., "Sources/**/*.swift")
    let filePattern: String?
    /// Filter by declaration name pattern (regex pattern)
    let namePattern: String?
    /// Whether to include excluded items in the filter results
    let includeExcluded: Bool

    init(
        ids: [Int]? = nil,
        types: [DeclarationType]? = nil,
        filePattern: String? = nil,
        namePattern: String? = nil,
        includeExcluded: Bool = false
    ) {
        self.ids = ids
        self.types = types
        self.filePattern = filePattern
        self.namePattern = namePattern
        self.includeExcluded = includeExcluded
    }

    var isEmpty: Bool {
        ids == nil && types == nil && filePattern == nil && namePattern == nil
    }

    func matchesId(_ item: ReportItem) -> Bool {
        guard let ids, !ids.isEmpty else { return true }
        return ids.contains(item.id)
    }

    func matchesType(_ item: ReportItem) -> Bool {
        guard let types, !types.isEmpty else { return true }
        return types.contains(item.type)
    }

    func matchesFilePattern(_ item: ReportItem) -> Bool {
        guard let filePattern, !filePattern.isEmpty else { return true }
        return globMatch(pattern: filePattern, path: item.file)
    }

    func matchesNamePattern(_ item: ReportItem) -> Bool {
        guard let namePattern, !namePattern.isEmpty else { return true }
        do {
            let regex = try Regex(namePattern)
            return item.name.contains(regex)
        } catch {
            return false
        }
    }

    /// Checks if an item matches all specified criteria
    func matches(_ item: ReportItem) -> Bool {
        matchesId(item) && matchesType(item) && matchesFilePattern(item) && matchesNamePattern(item)
    }

    // Simple glob pattern matching supporting * and ** wildcards
    private func globMatch(pattern: String, path: String) -> Bool {
        let regexPattern = globToRegex(pattern)
        do {
            let regex = try Regex(regexPattern)
            return path.contains(regex)
        } catch {
            return false
        }
    }

    // Converts a glob pattern to a regex pattern
    private func globToRegex(_ glob: String) -> String {
        var result = ""
        var i = glob.startIndex

        while i < glob.endIndex {
            let char = glob[i]

            switch char {
            case "*":
                let nextIndex = glob.index(after: i)
                if nextIndex < glob.endIndex && glob[nextIndex] == "*" {
                    // ** matches any path segment including /
                    result += ".*"
                    i = glob.index(after: nextIndex)
                    continue
                } else {
                    // * matches anything except /
                    result += "[^/]*"
                }
            case "?":
                result += "[^/]"
            case ".":
                result += "\\."
            case "/":
                result += "/"
            case "[":
                result += "["
            case "]":
                result += "]"
            case "\\":
                result += "\\\\"
            case "^", "$", "+", "{", "}", "|", "(", ")":
                result += "\\\(char)"
            default:
                result.append(char)
            }

            i = glob.index(after: i)
        }

        return result
    }
}
