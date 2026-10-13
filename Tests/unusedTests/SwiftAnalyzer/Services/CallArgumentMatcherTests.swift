import Testing
@testable import unused

struct CallArgumentMatcherTests {
    @Test(arguments: [MemberKind.function, .initializer, .subscript])
    func matchingKindsAcceptExactLabels(kind: MemberKind) {
        let signature = MemberSignature(
            kind: kind, name: "member", parameterLabels: ["_", "named"],
            parameterTypes: ["Int", "String"]
        )
        let call = CallUsage(kind: kind, argumentLabels: ["_", "named"])

        #expect(CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func differentKindsDoNotMatchEvenWithIdenticalLabels() {
        let signature = MemberSignature(kind: .initializer, name: "init", parameterLabels: ["value"])
        let call = CallUsage(kind: .subscript, argumentLabels: ["value"])

        #expect(!CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func emptyArgumentListRequiresNoRequiredParameters() {
        let call = CallUsage(kind: .initializer)
        let empty = MemberSignature(kind: .initializer, name: "init")
        let required = MemberSignature(kind: .initializer, name: "init", parameterLabels: ["value"])
        let defaulted = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value", "other"],
            defaultParameterIndices: [0, 1]
        )

        #expect(CallArgumentMatcher().matches(call, signature: empty))
        #expect(!CallArgumentMatcher().matches(call, signature: required))
        #expect(CallArgumentMatcher().matches(call, signature: defaulted))
    }

    @Test
    func labelsMustMatchInOrderAndRequiredArgumentsCannotBeDroppedOrAdded() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["first", "second"]
        )
        let invalidLabels = [
            ["second", "first"], ["first"], ["first", "second", "third"],
            ["first", "other"], ["_", "second"]
        ]

        for labels in invalidLabels {
            let call = CallUsage(kind: .initializer, argumentLabels: labels)
            #expect(!CallArgumentMatcher().matches(call, signature: signature))
        }
    }

    @Test
    func defaultedParametersCanBeOmittedAtTheBeginningMiddleAndEnd() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["first", "required", "middle", "last"],
            defaultParameterIndices: [0, 2, 3]
        )
        let validLabels = [
            ["required"], ["first", "required"], ["required", "middle"],
            ["required", "last"], ["first", "required", "middle", "last"]
        ]

        for labels in validLabels {
            let call = CallUsage(kind: .initializer, argumentLabels: labels)
            #expect(CallArgumentMatcher().matches(call, signature: signature))
        }
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["first", "last"]), signature: signature
        ))
    }

    @Test
    func repeatedLabelsBacktrackAcrossDefaultedParameters() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value", "value", "end"],
            defaultParameterIndices: [0]
        )

        #expect(CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["value", "end"]), signature: signature
        ))
        #expect(CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["value", "value", "end"]), signature: signature
        ))
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["end"]), signature: signature
        ))
    }

    @Test
    func labeledVariadicsAcceptZeroOneOrSeveralElements() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["values"],
            parameterTypes: ["Int..."], variadicParameterIndices: [0]
        )

        for labels in [[], ["values"], ["values", "_"], ["values", "_", "_"]] {
            #expect(CallArgumentMatcher().matches(
                CallUsage(kind: .initializer, argumentLabels: labels), signature: signature
            ))
        }
        for labels in [["_"], ["values", "values"], ["values", "other"]] {
            #expect(!CallArgumentMatcher().matches(
                CallUsage(kind: .initializer, argumentLabels: labels), signature: signature
            ))
        }
    }

    @Test
    func unlabeledVariadicsAcceptOnlyUnlabeledElements() {
        let signature = MemberSignature(
            kind: .subscript, name: "subscript", parameterLabels: ["_"],
            parameterTypes: ["Int..."], variadicParameterIndices: [0]
        )

        for labels in [[], ["_"], ["_", "_", "_"]] {
            #expect(CallArgumentMatcher().matches(
                CallUsage(kind: .subscript, argumentLabels: labels), signature: signature
            ))
        }
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .subscript, argumentLabels: ["index"]), signature: signature
        ))
    }

    @Test
    func variadicsDoNotConsumeFollowingRequiredLabeledParameters() {
        let signature = MemberSignature(
            kind: .subscript, name: "subscript", parameterLabels: ["values", "limit"],
            parameterTypes: ["Int...", "Int"], variadicParameterIndices: [0]
        )

        for labels in [["limit"], ["values", "limit"], ["values", "_", "_", "limit"]] {
            #expect(CallArgumentMatcher().matches(
                CallUsage(kind: .subscript, argumentLabels: labels), signature: signature
            ))
        }
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .subscript, argumentLabels: ["values", "_"]), signature: signature
        ))
    }

    @Test
    func defaultsAndVariadicsComposeWithoutSkippingRequiredParameters() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["prefix", "values", "end", "suffix"],
            parameterTypes: ["String", "Int...", "String", "String"],
            defaultParameterIndices: [0, 3], variadicParameterIndices: [1]
        )

        for labels in [["end"], ["values", "_", "end"], ["prefix", "end", "suffix"]] {
            #expect(CallArgumentMatcher().matches(
                CallUsage(kind: .initializer, argumentLabels: labels), signature: signature
            ))
        }
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["prefix", "values", "_"]), signature: signature
        ))
    }

    @Test
    func trailingClosureCanOmitAClosureParameterLabel() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value", "completion"],
            parameterTypes: ["Int", "@Sendable()->Void"]
        )
        let call = CallUsage(kind: .initializer, argumentLabels: ["value", "_"], hasTrailingClosure: true)

        #expect(CallArgumentMatcher().matches(call, signature: signature))
        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["value", "_"]), signature: signature
        ))
    }

    @Test
    func trailingClosureCanFollowOmittedDefaultsAndVariadicElements() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["options", "values", "completion"],
            parameterTypes: ["Int", "String...", "()->Void"],
            defaultParameterIndices: [0], variadicParameterIndices: [1]
        )

        for labels in [["_"], ["values", "_"], ["values", "_", "_"]] {
            #expect(CallArgumentMatcher().matches(
                CallUsage(kind: .initializer, argumentLabels: labels, hasTrailingClosure: true),
                signature: signature
            ))
        }
        #expect(!CallArgumentMatcher().matches(CallUsage(kind: .initializer), signature: signature))
    }

    @Test
    func multipleTrailingClosuresKeepSubsequentLabels() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion", "failure"],
            parameterTypes: ["()->Void", "(Error)->Void"]
        )

        #expect(CallArgumentMatcher().matches(
            CallUsage(
                            kind: .initializer, argumentLabels: ["_", "failure"],
                            hasTrailingClosure: true, trailingClosureIndex: 0
                        ),
            signature: signature
        ))
        #expect(!CallArgumentMatcher().matches(
            CallUsage(
                            kind: .initializer, argumentLabels: ["_", "other"],
                            hasTrailingClosure: true, trailingClosureIndex: 0
                        ),
            signature: signature
        ))
    }

    @Test
    func trailingClosureLabelOmissionDoesNotApplyToOrdinaryArguments() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value", "completion"],
            parameterTypes: ["()->Void", "()->Void"]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_"], hasTrailingClosure: true, trailingClosureIndex: 1
        )

        #expect(!CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func laterTrailingClosureLabelsCannotAlsoBeOmitted() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion", "failure"],
            parameterTypes: ["()->Void", "(Error)->Void"]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_"], hasTrailingClosure: true, trailingClosureIndex: 0
        )

        #expect(!CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func trailingClosureDoesNotSupplyALabeledNonClosureParameter() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["value"], parameterTypes: ["Int"]
        )

        #expect(!CallArgumentMatcher().matches(
            CallUsage(kind: .initializer, argumentLabels: ["_"], hasTrailingClosure: true),
            signature: signature
        ))
    }

    @Test
    func trailingClosurePreservesGenericAndUnavailableParameterTypesConservatively() {
        let generic = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion"],
            parameterTypes: ["T"], genericParameters: ["T"]
        )
        let unavailable = MemberSignature(kind: .initializer, name: "init", parameterLabels: ["completion"])
        let call = CallUsage(kind: .initializer, argumentLabels: ["_"], hasTrailingClosure: true)

        #expect(CallArgumentMatcher().matches(call, signature: generic))
        #expect(CallArgumentMatcher().matches(call, signature: unavailable))
    }

    @Test(arguments: ["Completion", "Namespace.Completion", "Callback"])
    func trailingClosuresKeepAliasAndEnclosingGenericParameterTypesWithoutLocalGenericMetadata(type: String) {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion"], parameterTypes: [type]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["_"], hasTrailingClosure: true,
            trailingClosureIndex: 0, enclosingTypePath: ["Container"]
        )

        #expect(signature.genericParameters.isEmpty)
        #expect(CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test(arguments: ["Int", "Swift.Int"])
    func preciseTrailingClosureIndicesDoNotMakeKnownIntegerTypesCompatible(type: String) {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion"], parameterTypes: [type]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["_"], hasTrailingClosure: true, trailingClosureIndex: 0
        )

        #expect(!CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func preciseTrailingClosureIndexSeparatesOrdinaryArgumentsFromAdditionalClosures() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["_", "completion", "failure"],
            parameterTypes: ["()->Void", "Completion", "(Error)->Void"]
        )
        let valid = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_", "failure"],
            hasTrailingClosure: true, trailingClosureIndex: 1
        )
        let missingLaterLabel = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_", "_"],
            hasTrailingClosure: true, trailingClosureIndex: 1
        )
        let wrongLaterLabel = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_", "other"],
            hasTrailingClosure: true, trailingClosureIndex: 1
        )

        #expect(CallArgumentMatcher().matches(valid, signature: signature))
        #expect(!CallArgumentMatcher().matches(missingLaterLabel, signature: signature))
        #expect(!CallArgumentMatcher().matches(wrongLaterLabel, signature: signature))
    }

    @Test
    func preciseTrailingClosureIndexUsesArgumentPositionsWhenDefaultsAreOmitted() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["option", "_", "completion", "failure"],
            parameterTypes: ["Int", "()->Void", "Callback", "(Error)->Void"], defaultParameterIndices: [0]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["_", "_", "failure"],
            hasTrailingClosure: true, trailingClosureIndex: 1
        )

        #expect(CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func preciseTrailingClosureIndexFollowsAllVariadicArguments() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["values", "completion", "failure"],
            parameterTypes: ["Int...", "Completion", "(Error)->Void"], variadicParameterIndices: [0]
        )
        let call = CallUsage(
            kind: .initializer, argumentLabels: ["values", "_", "_", "failure"],
            hasTrailingClosure: true, trailingClosureIndex: 2
        )

        #expect(CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test
    func aTrailingClosureIndexWithoutATrailingClosureDoesNotPermitLabelOmission() {
        let signature = MemberSignature(
            kind: .initializer, name: "init", parameterLabels: ["completion"], parameterTypes: ["()->Void"]
        )
        let call = CallUsage(kind: .initializer, argumentLabels: ["_"], trailingClosureIndex: 0)

        #expect(!CallArgumentMatcher().matches(call, signature: signature))
    }

    @Test(arguments: [MemberKind.initializer, .subscript])
    func sameLabelOverloadsWithDifferentParameterTypesBothMatch(kind: MemberKind) {
        let integer = MemberSignature(
            kind: kind, name: "member", parameterLabels: ["value"], parameterTypes: ["Int"]
        )
        let string = MemberSignature(
            kind: kind, name: "member", parameterLabels: ["value"], parameterTypes: ["String"]
        )
        let call = CallUsage(kind: kind, argumentLabels: ["value"])

        #expect(CallArgumentMatcher().matches(call, signature: integer))
        #expect(CallArgumentMatcher().matches(call, signature: string))
    }

    @Test
    func receiverContextAndSignatureEffectsDoNotFilterLabelCompatibleCalls() {
        let signature = MemberSignature(
            kind: .subscript, name: "subscript", isStatic: true, parameterLabels: ["_"],
            parameterTypes: ["T"], resultType: "String", genericParameters: ["T"],
            isAsync: true, isThrowing: true
        )
        let call = CallUsage(
            kind: .subscript, receiverType: "Namespace.Owner", argumentLabels: ["_"],
            enclosingTypePath: ["Other", "Scope"]
        )

        #expect(CallArgumentMatcher().matches(call, signature: signature))
    }
}
