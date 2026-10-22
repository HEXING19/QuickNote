/// Hover previews the note without focus; a click commits an editing session.
/// Times use the monotonic clock supplied by the AppKit host.
public struct DrawerInteraction {
    public enum State: Equatable { case hidden, hovered, editing }
    public enum Action: Equatable { case expandHandle, collapseHandle }
    public private(set) var state: State = .hidden
    private var outsideSince: Double?
    private var suppressUntilExit = false
    public let leaveDelay: Double

    public init(leaveDelay: Double = 0.2) { self.leaveDelay = leaveDelay }
    public mutating func beginEditing() { state = .editing; outsideSince = nil }
    public mutating func didHide() {
        state = .hidden; outsideSince = nil; suppressUntilExit = true
    }
    public mutating func update(insideHandle: Bool, insidePanel: Bool = false, buttonDown: Bool, now: Double) -> Action? {
        switch state {
        case .hidden:
            if !insideHandle { suppressUntilExit = false }
            if insideHandle && !buttonDown && !suppressUntilExit {
                state = .hovered; outsideSince = nil; return .expandHandle
            }
        case .hovered:
            if insideHandle || insidePanel || buttonDown { outsideSince = nil }
            else if let since = outsideSince {
                if now - since >= leaveDelay {
                    state = .hidden; outsideSince = nil
                    return .collapseHandle
                }
            } else { outsideSince = now }
        case .editing: break
        }
        return nil
    }
}
