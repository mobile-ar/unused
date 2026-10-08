import Synchronization
import Testing
@testable import unused

struct ProtocolResolverProgressTests {
    @Test func failedProtocolLookupsReportCompletionAndElapsedTime() async throws {
        let updates = Mutex<[ProgressUpdate]>([])
        let finishLines = Mutex<Int>(0)
        let protocolNames: Set<String> = [
            "CompletelyFakeProgressProtocolThatDoesNotExistOne",
            "CompletelyFakeProgressProtocolThatDoesNotExistTwo"
        ]
        let resolver = ProtocolResolver(
            protocolRequirements: [:],
            protocolInheritance: [:],
            projectDefinedProtocols: [],
            importedModules: [],
            conformedProtocols: protocolNames,
            swiftInterfaceClient: SwiftInterfaceClient(),
            progressTrackerFactory: { total, prefix in
                ProgressTracker(
                    total: total,
                    prefix: prefix,
                    elapsed: { .milliseconds(25) },
                    renderInterval: .zero,
                    render: { update in updates.withLock { $0.append(update) } },
                    finishLine: { finishLines.withLock { $0 += 1 } }
                )
            }
        )

        await resolver.resolveExternalProtocols()

        let capturedUpdates = updates.withLock { $0 }
        #expect(capturedUpdates.map(\.prefix) == [
            "Analyzing external protocols...",
            "Analyzing external protocols..."
        ])
        #expect(capturedUpdates.map(\.current) == [1, 2])
        #expect(capturedUpdates.map(\.total) == [2, 2])
        #expect(capturedUpdates.map(\.estimatedRemaining) == [.milliseconds(25), .zero])
        #expect(capturedUpdates.map(\.elapsed) == [.milliseconds(25), .milliseconds(25)])
        #expect(finishLines.withLock { $0 } == 1)
        #expect(Set(resolver.protocolRequirements.keys) == protocolNames)
        for protocolName in protocolNames {
            #expect(resolver.protocolRequirements[protocolName] == Set<String>())
        }

        let completion = try #require(capturedUpdates.last)
        #expect(ProgressBarFormatter().render(completion).contains("Done in 25ms"))
    }

    @Test func projectDefinedAndCachedProtocolsDoNotRenderProgress() async {
        let updates = Mutex<[ProgressUpdate]>([])
        let finishLines = Mutex<Int>(0)
        let trackerTotals = Mutex<[Int]>([])
        let requirements: [String: Set<String>] = [
            "ProjectProtocol": ["projectMethod"],
            "CachedExternalProtocol": ["cachedMethod"],
            "CachedEmptyProtocol": []
        ]
        let inheritance: [String: Set<String>] = [
            "ProjectProtocol": ["CachedExternalProtocol"]
        ]
        let resolver = ProtocolResolver(
            protocolRequirements: requirements,
            protocolInheritance: inheritance,
            projectDefinedProtocols: ["ProjectProtocol", "UncachedProjectProtocol"],
            importedModules: [],
            conformedProtocols: [
                "ProjectProtocol",
                "UncachedProjectProtocol",
                "CachedExternalProtocol",
                "CachedEmptyProtocol"
            ],
            swiftInterfaceClient: SwiftInterfaceClient(),
            progressTrackerFactory: { total, prefix in
                trackerTotals.withLock { $0.append(total) }
                return ProgressTracker(
                    total: total,
                    prefix: prefix,
                    elapsed: { .milliseconds(25) },
                    renderInterval: .zero,
                    render: { update in updates.withLock { $0.append(update) } },
                    finishLine: { finishLines.withLock { $0 += 1 } }
                )
            }
        )

        await resolver.resolveExternalProtocols()

        #expect(trackerTotals.withLock { $0 } == [0])
        #expect(updates.withLock { $0.isEmpty })
        #expect(finishLines.withLock { $0 } == 0)
        #expect(resolver.protocolRequirements == requirements)
        #expect(resolver.protocolInheritance == inheritance)
    }
}
