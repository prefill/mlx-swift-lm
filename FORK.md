# Model-load admission in this fork

This fork adds an optional policy that lets an application reject GPU-capable model-loading stages after it retires a load.

## Why the application needs a policy

A model load can outlive the application's decision to stop using it. Weight loading dispatches work to GCD, and a model component can load later on first use. Cancelling the original Swift task does not check application-owned revocation at these points.

This matters when an application prepares to enter the background. On iOS and tvOS, Apple documents restrictions on background GPU use and asks applications to stop submitting new Metal work when deactivated. That guidance motivates an admission check. It does not establish that this fork meets a device's lifecycle timing requirements. See [Preparing your Metal app to run in the background](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background).

## What the library provides

[`ModelLoadAdmission`](Libraries/MLXLMCommon/ModelLoadAdmission.swift) defines a synchronous `perform` operation. The application installs its implementation through `ModelLoading.$admission.withValue(policy)` around a factory load. With no policy, the loader calls the original operations directly.

The library checks admission around registered model and processor construction, model-provided loading callbacks, component setup, and checkpoint preparation, application, and evaluation. The LLM factory also checks admission around the model's message-generator constructor. Blocking checkpoint reads remain outside admission. The existing CPU-stream checkpoint reader and its concurrent loading algorithm are unchanged.

The async weight loader captures the policy before dispatching work to GCD. It passes the captured policy to the worker explicitly. Deferred components retain the original policy for later construction and checkpoint preparation. A failed component load remains pending with that policy, so a later task's different policy does not authorize the old component.

See [using model-load admission](Libraries/MLXLMCommon/Documentation.docc/model-load-admission.md) for the API contract and a factory-call example.

## What the application owns

The policy must call the operation exactly once on the current thread, or throw before entry. The application owns synchronization of admission and revocation, the stream choices, and any required stream drain before `perform` returns or throws. A check that races with revocation is not enough.

The library does not provide an app lifecycle controller. The hook does not interrupt an admitted operation, govern inference after loading, or intercept every GPU operation. Custom loaders and callbacks that dispatch work elsewhere need their own admission boundaries.

The separate ParoQuant loader throws `ParoQuantError.loadAdmissionUnsupported` before reading its checkpoint when a policy is installed. With no policy, its existing behavior remains available.

## Dependency revisions

The integration documented here combines upstream commit `128f49f1db38ea7b949f2ebb60967def8b76f58e` with the admission fix in `7b67e189e8a052351883aa3696ea35248e3a9a8a`. Its `Package.swift` requires `mlx-swift` 0.33.x.

An application pinned to the full `7b67e189e8a052351883aa3696ea35248e3a9a8a` revision keeps that revision when this fork's `main` advances. That revision declares `mlx-swift` 0.32.3 or later within 0.32.x. Moving to the integrated main branch changes the upstream source and dependency range as well as retaining this fix. Validation against the older pin does not validate the newer dependency graph.

## Verification of the current-main integration

On macOS 27.0.1 with Xcode 27.1, 80 selected tests passed across `ModelLoadAdmissionTests`, `ParoQuantCheckpointTests`, `LoadWeightsTests`, `ModelComponentTests`, `EmbeddingGemma2Tests`, and `ModelMemoryTests`. These tests use small fixtures without downloading model checkpoints.

The full `pre-commit run --all-files` check passed with upstream's pinned swift-format 603.0.0. `MLXLMCommon` documentation passed a strict DocC conversion using Xcode-generated symbol graphs. An ordinary Xcode documentation build also passed. A strict build of all dependency documentation stopped on unresolved references in the unchanged `mlx-swift` dependency.

## Evidence limits

The admission tests check rejection before selected callbacks, policy retention across GCD and deferred loading, the nil-policy registry result, and rejection of unsupported ParoQuant loads. These checks do not reproduce a device crash or prove background execution safety. This fork makes no claim about device lifecycle latency, interrupted GPU execution, or loading and inference performance.

## AI use

AI agents generated the admission implementation, its added tests, and these fork notes, and performed independent reviews. An upstream submission still requires the contributor to read and understand the code and description.
