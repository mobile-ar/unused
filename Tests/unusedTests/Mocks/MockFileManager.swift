//
//  Created by Fernando Romiti on 08/02/2025.
//

import Foundation
@testable import unused

final class MockFileManager: FileManagerProtocol, @unchecked Sendable {
    var homeDirectory: URL = URL(fileURLWithPath: "/Users/testuser")
    var currentDirectory: String = "/Users/testuser"
    var existingPaths: Set<String> = []
    var fileContents: [String: Data] = [:]
    var createdDirectories: [String] = []
    var createdFiles: [String] = []
    var writtenFiles: [String: String] = [:]
    var removedItems: [URL] = []
    var removedPaths: [String] = []

    var homeDirectoryForCurrentUser: URL { homeDirectory }
    var currentDirectoryPath: String { currentDirectory }

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws {
        createdDirectories.append(path)
        existingPaths.insert(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        createdDirectories.append(url.path)
        existingPaths.insert(url.path)
    }

    func contents(atPath path: String) -> Data? {
        fileContents[path]
    }

    func createFile(atPath path: String, contents: Data?) {
        createdFiles.append(path)
        existingPaths.insert(path)
        if let contents {
            fileContents[path] = contents
        }
    }

    func writeString(_ string: String, toFile path: String) throws {
        writtenFiles[path] = string
        fileContents[path] = string.data(using: .utf8)
        existingPaths.insert(path)
    }

    func removeItem(at url: URL) throws {
        removedItems.append(url)
        existingPaths.remove(url.path)
    }

    func removeItem(atPath path: String) throws {
        removedPaths.append(path)
        existingPaths.remove(path)
    }

    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) -> FileManager.DirectoryEnumerator? {
        nil
    }

    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        nil
    }

    func setFileContent(_ content: String, atPath path: String) {
        fileContents[path] = content.data(using: .utf8)
        existingPaths.insert(path)
    }

    func reset() {
        existingPaths.removeAll()
        fileContents.removeAll()
        createdDirectories.removeAll()
        createdFiles.removeAll()
        writtenFiles.removeAll()
        removedItems.removeAll()
        removedPaths.removeAll()
    }
}
