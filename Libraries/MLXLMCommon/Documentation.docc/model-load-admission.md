# Use a model-load admission policy

Install a caller-owned policy to reject GPU-capable loading stages after your application retires a load.

## Supply your application's policy

Implement ``ModelLoadAdmission`` in your application. Its synchronous requirement is:

```swift
func perform<Result>(_ operation: () throws -> Result) throws -> Result
```

Call `operation` exactly once on the current thread, or throw before entering it. Coordinate that decision with your application's revocation state. Complete any required stream drain before returning or throwing, including when `operation` throws. The policy must be `Sendable`.

Keep lifecycle state, revocation, stream selection, and draining in your application. The library does not supply these decisions.

## Install the policy around the factory call

Pass your policy and tokenizer loader to the load operation. This example loads a model from a local directory:

```swift
import Foundation
import MLXLLM
import MLXLMCommon

func loadLocalModel(
	from directory: URL,
	using tokenizerLoader: any TokenizerLoader,
	admission: any ModelLoadAdmission
) async throws -> ModelContainer {
	try await ModelLoading.$admission.withValue(admission) {
		try await LLMModelFactory.shared.loadContainer(
			from: directory,
			using: tokenizerLoader
		)
	}
}
```

Omit the task-local policy to preserve ordinary loading. The default value of ``ModelLoading/admission`` is `nil`.

## Account for deferred work

Keep the policy's revocation state valid for the lifetime of the load and its deferred components. The weight loader captures the policy before dispatching to GCD. Deferred components retain the same policy when they load later, even outside the original `withValue` scope. A later task's different policy does not replace it.

Expect separate calls to `perform` for synchronous loading stages. The loader does not hold admission across an `await` or checkpoint I/O. Revocation during checkpoint I/O can therefore reject the next admitted stage.

## Handle unsupported paths

Handle ``ParoQuantError/loadAdmissionUnsupported`` when a ParoQuant load has a non-nil policy. Its separate loader does not implement these admission boundaries.

Apply your application's admission rules separately to inference and custom loading code. This hook does not interrupt an operation that has already entered `perform`, select streams, or intercept work that a callback dispatches elsewhere.
