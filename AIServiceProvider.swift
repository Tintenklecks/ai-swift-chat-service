import Foundation

enum AIProvider: String {
    case openAI
    case claude
    case gemini
    case groq
    

    func setAPIKey(_ key: String) {
        UserDefaults.standard.setValue(key, forKey: "API_KEY_\(self.rawValue)")
    }
    
    var apiKey: String {
        UserDefaults.standard.string(forKey: "API_KEY_\(self.rawValue)") ?? ""
    }
    
    var provider: AIServiceProvider {
        switch self {
        case .openAI:
            return OpenAIProvider()
        case .claude:
            return ClaudeProvider()
        case .gemini:
            return GeminiProvider()
        case .groq:
            return GroqProvider()
        }
    }
}
