//
//  Item.swift
//  unused
//
//  Created by Fernando Romiti on 09/10/2024.
//

import Foundation

class Item {
    var file: String
    var line: String
    var at: Int
    var type: String?
    var name: String?
    var modifiers: [String]?

    init(file: String, line: String, at: Int) {
        self.file = file
        self.line = line
        self.at = at + 1

        if let match = line.range(of: "(func|let|var|class|enum|struct|protocol|actor|extension)\\s+(\\w+)", options: .regularExpression) {
            let captures = line[match].split(separator: " ")
            self.type = String(captures[0])
            self.name = String(captures[1])
        }
    }

    func getModifiers() -> [String] {
        if let modifiers = self.modifiers {
            return modifiers
        }
        if let match = line.range(of: "(.*?)\(type ?? "")", options: .regularExpression) {
            self.modifiers = line[match].split(separator: " ").compactMap { String($0) }
        }
        return self.modifiers ?? []
    }

    func serialize() -> String {
        return "Item< \(type?.green ?? "") \(name?.yellow ?? "") [\(getModifiers().joined(separator: " ").cyan)] from: \(file):\(at):0>"
    }

    func toXcode() -> String {
        return "\(fullFilePath()):\(at):0: warning: \(type ?? "") \(name ?? "") is unused"
    }

    func fullFilePath() -> String {
        return FileManager.default.currentDirectoryPath + "/" + file
    }
}
