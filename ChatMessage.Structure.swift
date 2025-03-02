import Foundation

struct AIChatMessage {
    let role: AIChatRole
    let content: String
    let timestamp = Date()
}

enum AIChatRole: String {
    case system
    case user
    case assistant
    case tool
}

