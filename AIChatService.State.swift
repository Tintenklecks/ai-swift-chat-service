import SwiftUI

enum AIChatServiceState: Equatable {
    case idle
    case active
    case error(String)
    case done

    var color: Color {
        switch self {
        case .idle:
            return .gray
        case .active:
            return .blue
        case .error:
            return .red
        case .done:
            return .green
        }
    }

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .active:
            return "Active"
        case .error(let error):
            return "Error: \(error)"
        case .done:
            return "Done"
        }
    }
}
