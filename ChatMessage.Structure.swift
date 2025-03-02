import Foundation

struct AIChatMessage {
    let role: AIChatRole
    let content: String
}

enum AIChatRole: String {
    case system
    case user
    case assistant
    case tool
}

