// Copyright © 2026 Apple Inc.

/// Controls entry to synchronous model-loading work that can submit GPU operations.
///
/// An implementation must invoke `operation` exactly once on the calling thread, or throw
/// before entering it. It owns the revocation check and any stream drain required before
/// returning or throwing. The loader never holds admission across an `await` or checkpoint I/O.
/// This policy does not select streams or cover inference after loading.
public protocol ModelLoadAdmission: Sendable {
    func perform<Result>(_ operation: () throws -> Result) throws -> Result
}

/// Per-load policy for registered constructors, component loading and checkpoint preparation.
///
/// Set `$admission.withValue(policy)` around the async factory call. The loaders capture the
/// policy before dispatching work, and deferred components retain it for their later load.
/// A nil policy preserves ordinary loading. Custom loaders must implement their own boundaries;
/// the ParoQuant loader rejects a non-nil policy because its separate path is not covered.
public enum ModelLoading {
    @TaskLocal public static var admission: (any ModelLoadAdmission)?

    package static func perform<Result>(
        admission: (any ModelLoadAdmission)? = ModelLoading.admission,
        _ operation: () throws -> Result
    ) throws -> Result {
        if let admission {
            return try admission.perform(operation)
        }
        return try operation()
    }
}
