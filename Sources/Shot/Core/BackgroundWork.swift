import Foundation

/// Explicitly propagates cancellation across the detached worker boundary.
/// System encoders can finish a non-interruptible call, but no later stage
/// starts after cancellation and their result cannot escape to the UI.
enum BackgroundWork {
    static func run<Value>(
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: priority) {
            try Task.checkCancellation()
            return try autoreleasepool(invoking: operation)
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }
}
