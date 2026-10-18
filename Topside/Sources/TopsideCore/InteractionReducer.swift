import Foundation

public enum Region: Equatable, Hashable, Sendable { case clock, battery, spotify }

public enum IslandMode: Equatable, Sendable {
    case collapsed
    case peek(Region)       // hover preview
    case expanded(Region)   // pinned by click

    public var region: Region? {
        switch self {
        case .collapsed: return nil
        case .peek(let r), .expanded(let r): return r
        }
    }
}

public struct InteractionState: Equatable, Sendable {
    public var mode: IslandMode = .collapsed
    /// Region currently under the pointer; nil = pointer outside any hoverable region.
    public var hovered: Region? = nil
    public var suppressed = false
    public var dragging = false
    /// Bumped whenever pending timers must be considered stale.
    public var token = 0
    public init() {}
}

public enum InteractionEvent: Equatable, Sendable {
    case pointerMoved(Region?)
    case dwellElapsed(token: Int)
    case graceElapsed(token: Int)
    case clicked(Region)
    case outsideClick
    case escape
    case setSuppressed(Bool)
    case dragBegan
    case dragEnded
}

public enum InteractionEffect: Equatable, Sendable {
    case startDwell(token: Int, delay: TimeInterval)
    case startGrace(token: Int, delay: TimeInterval)
    case cancelTimers
}

/// Pure, deterministic. Timers live outside; stale timers are rejected by token.
public enum InteractionReducer {
    @discardableResult
    public static func reduce(_ s: inout InteractionState, _ event: InteractionEvent) -> [InteractionEffect] {
        switch event {

        case .pointerMoved(let region):
            guard region != s.hovered else { return [] }      // dwell counts from entry, not from last movement
            s.hovered = region
            s.token += 1
            guard !s.suppressed else { return [.cancelTimers] }
            switch s.mode {
            case .expanded:
                return [.cancelTimers]                          // pinned: pointer position is irrelevant
            case .collapsed:
                if region == nil { return [.cancelTimers] }
                return [.startDwell(token: s.token, delay: Timing.hoverDwell)]
            case .peek(let current):
                if let r = region {
                    if r != current { s.mode = .peek(r) }
                    return [.cancelTimers]
                }
                return [.startGrace(token: s.token, delay: Timing.leaveGrace)]
            }

        case .dwellElapsed(let token):
            guard token == s.token, !s.suppressed, s.mode == .collapsed, let r = s.hovered else { return [] }
            s.mode = .peek(r)
            return []

        case .graceElapsed(let token):
            guard token == s.token, !s.suppressed, !s.dragging, s.hovered == nil else { return [] }
            if case .peek = s.mode { s.mode = .collapsed }
            return []

        case .clicked(let r):
            guard !s.suppressed else { return [] }
            s.hovered = r
            s.token += 1
            s.mode = (s.mode == .expanded(r)) ? .collapsed : .expanded(r)   // at most one pinned panel
            return [.cancelTimers]

        case .outsideClick, .escape:
            s.token += 1
            s.mode = .collapsed
            return [.cancelTimers]

        case .setSuppressed(let on):
            s.suppressed = on
            s.token += 1
            if on { s.mode = .collapsed; s.hovered = nil; s.dragging = false }
            return [.cancelTimers]

        case .dragBegan:
            s.dragging = true
            s.token += 1
            return [.cancelTimers]

        case .dragEnded:
            s.dragging = false
            if case .peek = s.mode, s.hovered == nil, !s.suppressed {
                s.token += 1
                return [.startGrace(token: s.token, delay: Timing.leaveGrace)]
            }
            return []
        }
    }
}
