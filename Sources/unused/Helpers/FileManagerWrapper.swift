//
//  Created by Fernando Romiti on 08/02/2025.
//

import Foundation

protocol FileManagerProtocol {
    var homeDirectoryForCurrentUser: URL { get }
    var currentDirectoryPath: String { get }
    func fileExists(atPath path: String) -> Bool
    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func contents(atPath path: String) -> Data?
    func createFile(atPath path: String, contents: Data?)
    func writeString(_ string: String, toFile path: String) throws
    func removeItem(at url: URL) throws
    func removeItem(atPath path: String) throws
    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) -> FileManager.DirectoryEnumerator?
    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions) -> FileManager.DirectoryEnumerator?
}

struct FileManagerWrapper: FileManagerProtocol {
    var homeDirectoryForCurrentUser: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    var currentDirectoryPath: String {
        FileManager.default.currentDirectoryPath
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectory(atPath path: String, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: nil)
    }

    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    func createFile(atPath path: String, contents: Data?) {
        FileManager.default.createFile(atPath: path, contents: contents, attributes: nil)
    }

    func writeString(_ string: String, toFile path: String) throws {
        try string.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func removeItem(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
    }

    func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
    }
}
