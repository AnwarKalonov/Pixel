import Foundation

public enum EyeMood: String, CaseIterable, Equatable, Sendable {
    case idle
    case scanning
    case thinking
    case executing
    case sleeping

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Reading / Scanning"
        case .thinking: return "Thinking / Processing"
        case .executing: return "Executing / Clicking"
        case .sleeping: return "Sleeping"
        }
    }
}

public enum EyeStyle: String, CaseIterable, Codable, Sendable {
    case classic
    case expressive
    case stealth

    public var title: String {
        switch self {
        case .classic: return "Classic (Minimal white dots)"
        case .expressive: return "Expressive (Full movements & states)"
        case .stealth: return "Stealth (Subtle glow indicator)"
        }
    }
}

public enum ExpansionLevel: Int, Equatable, Sendable {
    case closed = 1
    case hoverPeek = 2
    case expanded = 3

    public var title: String {
        switch self {
        case .closed: return "Level 1: Closed"
        case .hoverPeek: return "Level 2: Hover Peek"
        case .expanded: return "Level 3: Full Expanded"
        }
    }
}
