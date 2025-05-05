import Foundation

class Unused {
    
    func find() {
        var items: [Item] = []
        let allFiles = try! FileManager.default.subpathsOfDirectory(atPath: ".").filter { $0.hasSuffix(".swift") } //&& !FileManager.default.isDirectory(atPath: $0)
        
        for file in allFiles {
            var fileItems = grabItems(file: file)
            fileItems = filterItems(items: fileItems)

            let (nonPrivateItems, privateItems) = fileItems.stablePartition { !$0.getModifiers().contains("private") && !$0.getModifiers().contains("fileprivate") }
            items += nonPrivateItems

            if !privateItems.isEmpty {
                findUsagesInFiles(files: [file], xibs: [], items: privateItems)
            }
        }

        print("Total items to be checked \(items.count)")

        items = Array(Set(items.compactMap { $0.name })).compactMap { name in items.first { $0.name == name } }
        print("Total unique items to be checked \(items.count)")

        print("Starting searching globally it can take a while".green)

        let xibs = try! FileManager.default.subpathsOfDirectory(atPath: ".").filter { $0.hasSuffix(".xib") }
        let storyboards = try! FileManager.default.subpathsOfDirectory(atPath: ".").filter { $0.hasSuffix(".storyboard") }

        findUsagesInFiles(files: allFiles, xibs: xibs + storyboards, items: items)
    }

    func ignoreFilesWithRegexps(files: [Item], regexps: [String]) -> [Item] {
        return files.filter { file in regexps.allSatisfy { regex in file.file.range(of: regex, options: .regularExpression) == nil } }
    }

    func ignoringRegexpsFromCommandLineArgs() -> [String] {
        var regexps: [String] = []
        var shouldSkipPredefinedIgnores = false

        var arguments = CommandLine.arguments
        while !arguments.isEmpty {
            let item = arguments.removeFirst()
            if item == "--ignore" {
                let regex = arguments.removeFirst()
                regexps.append(regex)
            }

            if item == "--skip-predefined-ignores" {
                shouldSkipPredefinedIgnores = true
            }
        }

        if !shouldSkipPredefinedIgnores {
            regexps += [
                "^Pods/",
                "fastlane/",
                "Tests.swift$",
                "Spec.swift$",
                "Tests/"
            ]
        }

        return regexps
    }

    func findUsagesInFiles(files: [String], xibs: [String], items: [Item]) {
        var items = items
        var usages = Array(repeating: 0, count: items.count)

        for file in files {
            let lines = try! String(contentsOfFile: file, encoding: .utf8)
                .components(separatedBy: .newlines)
                .compactMap { $0.replacingOccurrences(of: "^[^/]*//.*", with: "", options: .regularExpression) }
            let words = lines.joined(separator: "\n").components(separatedBy: .whitespacesAndNewlines)
            let wordCounts = Dictionary(words.compactMap { ($0, 1) }, uniquingKeysWith: +)

            for (i, item) in items.enumerated() {
                usages[i] += wordCounts[item.name ?? ""] ?? 0
            }

            let indexes = usages.enumerated().filter { $0.element >= 2 }.compactMap { $0.offset }
            for index in indexes.reversed() {
                usages.remove(at: index)
                items.remove(at: index)
            }
        }

//        for xib in xibs {
//            let lines = try! String(contentsOfFile: xib, encoding: .utf8).components(separatedBy: .newlines).compactMap { $0.replacingOccurrences(of: "^\\s*//.*", with: "", options: .regularExpression) }
//            let fullXML = lines.joined(separator: " ")
//            do {
//                let regEx = try Regex("(class|customClass)=\"([^\"]+)\"")
//                let classes = fullXML.matches(of: regEx).compactMap { $0.output[1] }
//                
//                let classCounts = Dictionary(classes.compactMap { ($0, 1) }, uniquingKeysWith: +)
//
//                for (i, item) in items.enumerated() {
//                    usages[i] += classCounts[item.name ?? ""] ?? 0
//                }
//
//                let indexes = usages.enumerated().filter { $0.element >= 2 }.compactMap { $0.offset }
//                for index in indexes.reversed() {
//                    usages.remove(at: index)
//                    items.remove(at: index)
//                }
//            } catch {
//                print("Failed to create regex")
//            }
//        }

        let regexps = ignoringRegexpsFromCommandLineArgs()
        items = ignoreFilesWithRegexps(files: items, regexps: regexps)

        if !items.isEmpty {
            if CommandLine.arguments.first == "xcode" {
                fputs(items.compactMap { $0.toXcode() }.joined(separator: "\n"), stderr)
            } else {
                print(items.compactMap { $0.serialize() }.joined(separator: "\n"))
            }
        }
    }

    func grabItems(file: String) -> [Item] {
        let lines = try! String(contentsOfFile: file, encoding: .utf8).components(separatedBy: .newlines).compactMap { $0.replacingOccurrences(of: "^\\s*//.*", with: "", options: .regularExpression) }
        return lines.enumerated().compactMap { (i, line) in
            line.range(of: "(func|let|var|class|enum|struct|protocol|actor|extension)\\s+\\w+", options: .regularExpression) != nil ? Item(file: file, line: line, at: i) : nil
        }
    }

    func filterItems(items: [Item]) -> [Item] {
        return items.filter { item in
            !(item.name?.hasPrefix("test") ?? false) &&
            !item.getModifiers().contains("@IBAction") &&
            !item.getModifiers().contains("override") &&
            !item.getModifiers().contains("@objc") &&
            !item.getModifiers().contains("@IBInspectable")
        }
    }
}
