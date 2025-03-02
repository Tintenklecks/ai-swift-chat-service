import SwiftUI

// Contract:
// - The API key is passed via the ChatAPI enum (e.g. AIProvider.claude.apiKey)"

protocol AIServiceProvider {
    var models: [String] { get }
    func setModel(_ newModel: String)
    func executeStream(messages: [AIChatMessage], responseText: Binding<String>) async throws
    func execute(messages: [AIChatMessage]) async throws -> String
}

// Protocol extension with helper methods
extension AIServiceProvider {
    func execute(messages: [AIChatMessage]) async throws -> String {
        var finalResponse = ""
        let binding = Binding(
            get: { finalResponse },
            set: { finalResponse = $0 }
        )
        
        try await executeStream(messages: messages, responseText: binding)
        return finalResponse
    }
    
    // Add a default implementation for handling stream completion
    func handleStreamCompletion(responseText: String, addMessage: (AIChatMessage) -> Void) {
        if !responseText.isEmpty {
            addMessage(AIChatMessage(role: .assistant, content: responseText))
        }
    }
}
