import Foundation

struct AIChatMessage: Identifiable {
    let id = UUID()
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

