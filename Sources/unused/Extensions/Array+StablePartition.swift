//
//  Array+StablePartition.swift
//  unused
//
//  Created by Fernando Romiti on 09/10/2024.
//

extension Array {
    
    func stablePartition(by condition: (Element) -> Bool) -> ([Element], [Element]) {
        var matching = [Element]()
        var nonMatching = [Element]()
        for element in self {
            if condition(element) {
                matching.append(element)
            } else {
                nonMatching.append(element)
            }
        }
        return (matching, nonMatching)
    }
    
}
