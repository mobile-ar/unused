struct CallArgumentMatcher {
    /// Types are deliberately not used to select overloads: without semantic
    /// resolution, implicit conversions and generic inference remain ambiguous.
    func matches(_ call: CallUsage, signature: MemberSignature) -> Bool {
        guard call.kind == signature.kind else { return false }
        let parameters = signature.parameterLabels
        let arguments = call.argumentLabels
        var memo: [Int: Bool] = [:]

        func labelMatches(parameter: Int, argument: Int) -> Bool {
            if parameters[parameter] == arguments[argument] { return true }
            let trailingIndex = call.trailingClosureIndex ?? arguments.lastIndex(of: "_")
            guard call.hasTrailingClosure, argument == trailingIndex,
                  arguments[argument] == "_" else { return false }
            // An unlabeled trailing closure can supply a labeled closure parameter.
            // Retain generic candidates too, since their inferred type is unavailable.
            guard parameter < signature.parameterTypes.count else { return true }
            let type = signature.parameterTypes[parameter]
            if type.contains("->") || signature.genericParameters.contains(type) { return true }
            // A nominal spelling may be a function typealias or an enclosing
            // generic parameter. Only reject types known not to accept closures.
            let nonClosureTypes: Set<String> = [
                "Bool", "String", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
                "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Float", "Double", "Void", "Never"
            ]
            let nominal = type.hasPrefix("Swift.") ? String(type.dropFirst(6)) : type
            return !nonClosureTypes.contains(nominal)
        }

        func match(parameter: Int, argument: Int) -> Bool {
            let key = parameter * (arguments.count + 1) + argument
            if let cached = memo[key] { return cached }
            let result: Bool
            if parameter == parameters.count {
                result = argument == arguments.count
            } else if signature.variadicParameterIndices.contains(parameter) {
                var compatible = match(parameter: parameter + 1, argument: argument)
                if argument < arguments.count, labelMatches(parameter: parameter, argument: argument) {
                    var next = argument + 1
                    compatible = compatible || match(parameter: parameter + 1, argument: next)
                    while !compatible, next < arguments.count, arguments[next] == "_" {
                        next += 1
                        compatible = match(parameter: parameter + 1, argument: next)
                    }
                }
                result = compatible
            } else {
                let omitted = signature.defaultParameterIndices.contains(parameter)
                    && match(parameter: parameter + 1, argument: argument)
                result = omitted || (argument < arguments.count
                    && labelMatches(parameter: parameter, argument: argument)
                    && match(parameter: parameter + 1, argument: argument + 1))
            }
            memo[key] = result
            return result
        }

        return match(parameter: 0, argument: 0)
    }
}
