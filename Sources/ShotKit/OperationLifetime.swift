/// A result may affect a session only while its operation is current.
/// Invalidating is synchronous; cancellation of system work is best effort.
public struct OperationLifetime: Sendable {
    public struct Token: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    private var generation: UInt64 = 0
    private var active: Token?

    public init() {}

    @discardableResult
    public mutating func begin() -> Token {
        generation &+= 1
        let token = Token(generation: generation)
        active = token
        return token
    }

    public func contains(_ token: Token) -> Bool { active == token }

    @discardableResult
    public mutating func finish(_ token: Token) -> Bool {
        guard contains(token) else { return false }
        active = nil
        return true
    }

    public mutating func invalidate() { active = nil }
    public var isActive: Bool { active != nil }
}
