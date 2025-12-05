//
//  Created by Fernando Romiti on 5/12/2025.
//

import Foundation

func getSwiftFiles(in directory: URL) -> [URL] {
    var swiftFiles = [URL]()
    let fileManager = FileManager.default
    let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
    
    while let element = enumerator?.nextObject() as? URL {
        if !element.pathComponents.contains(".build") && element.pathExtension == "swift" {
            swiftFiles.append(element)
        }
    }

    return swiftFiles
}
