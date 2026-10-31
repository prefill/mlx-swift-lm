// Copyright © 2026 Apple Inc.

import Foundation
import MLXNN
import Testing

@testable import MLXLMCommon

struct RejectingModelLoadAdmission: ModelLoadAdmission {
    func perform<Result>(_ operation: () throws -> Result) throws -> Result {
        throw CancellationError()
    }
}

struct ModelLoadAdmissionTests {
    private final class EmptyModel: Module, BaseLanguageModel {}

    @Test
    func registryRejectsBeforePredicateOrConstructor() async throws {
        let registry = ModelTypeRegistry<Int>()
        await registry.registerModelType(
            "test",
            matches: { _ in
                Issue.record("Rejected load entered registry predicate")
                return true
            },
            creator: { _ in
                Issue.record("Rejected load entered model constructor")
                return 42
            })
        await #expect(throws: CancellationError.self) {
            try await ModelLoading.$admission.withValue(RejectingModelLoadAdmission()) {
                try await registry.createModel(configuration: Data(), modelType: "test")
            }
        }
    }

    @Test
    func registryWithoutPolicyPreservesResult() async throws {
        let registry = ModelTypeRegistry<Int>(creators: ["test": { _ in 42 }])
        #expect(try await registry.createModel(configuration: Data(), modelType: "test") == 42)
    }

    @Test
    func dispatchedWeightLoadRetainsPolicy() async throws {
        await #expect(throws: CancellationError.self) {
            try await ModelLoading.$admission.withValue(RejectingModelLoadAdmission()) {
                try await loadWeights(
                    modelDirectory: URL(fileURLWithPath: "/unused-admission-test"),
                    model: EmptyModel())
            }
        }
    }

    @Test
    func deferredComponentRetainsOriginalPolicy() async throws {
        let component = OnDemandComponent<Module>(.vision) {
            Issue.record("Rejected component entered constructor")
            return Module()
        }
        component.setSource(
            .init(
                urls: [], namespaces: [], perLayerQuantization: nil,
                admission: RejectingModelLoadAdmission(),
                prepare: { checkpoint in
                    Issue.record("Rejected component entered checkpoint preparation")
                    return checkpoint
                }))
        await #expect(throws: CancellationError.self) {
            try await component.loadInBackground()
        }
        #expect(!component.isLoaded)
    }
}
