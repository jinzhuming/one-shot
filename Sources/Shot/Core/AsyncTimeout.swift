import Foundation

/// Runs an asynchronous operation with a bounded wait while allowing the
/// underlying operation to finish cleanup after the caller has recovered.
///
/// A task group is deliberately not used here: structured task groups wait for
/// every child before returning, which would reintroduce the hang this helper
/// is intended to contain when a system API ignores cancellation.
@MainActor
enum AsyncTimeout {
    static func run<Value>(
        timeout: Duration,
        timeoutError: Error,
        onTimeout: @escaping () -> Void = {},
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let gate = CompletionGate<Value>()
        let operationTask = Task { @MainActor in
            do {
                gate.resume(returning: try await operation())
            } catch {
                gate.resume(throwing: error)
            }
        }
        let timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard gate.resume(throwing: timeoutError) else { return }
            onTimeout()
            operationTask.cancel()
        }

        do {
            let value = try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    gate.install(continuation)
                }
            }, onCancel: {
                operationTask.cancel()
                timeoutTask.cancel()
                gate.resume(throwing: CancellationError())
            })
            operationTask.cancel()
            timeoutTask.cancel()
            return value
        } catch {
            operationTask.cancel()
            timeoutTask.cancel()
            throw error
        }
    }
}

private final class CompletionGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    @discardableResult
    func resume(returning value: Value) -> Bool {
        resume(with: .success(value))
    }

    @discardableResult
    func resume(throwing error: Error) -> Bool {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Value, Error>) -> Bool {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
        return true
    }
}
