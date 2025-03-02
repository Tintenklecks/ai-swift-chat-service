import SwiftUI

class ClaudeProvider: NSObject, AIServiceProvider, URLSessionDataDelegate {
    internal var models: [String] = ["claude-3-5-haiku-latest", "claude-3-5-sonnet-latest", "claude-3-opus-latest"]

    private var model = "claude-3-5-haiku-latest"
   
    private var streamContinuation: CheckedContinuation<Void, Error>?
    private var responseBinding: Binding<String>?
    private var maxTokens: Int = 1024
    private let chatAPI = AIProvider.claude
    
    private var apiKey: String { AIProvider.claude.apiKey }

    func setModel(_ newModel: String) {
        model = newModel
    }
    
    func makeRequest(messages: [AIChatMessage], stream: Bool = true) throws -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw URLError(.badURL)
        }
            
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
        request
            .addValue(
                " \(apiKey)",
                forHTTPHeaderField: "x-api-key"
            )
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages
                .filter { $0.role != .system && $0.role != .tool }
                .map { message in
                    [
                        "role": convertRole(message.role),
                        "content": message.content
                    ]
                },
            "stream": stream
        ]
            
        if let systemContent: String? = messages.first(where: { $0.role == .system })?.content {
            body["system"] = systemContent
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func executeStream(messages: [AIChatMessage], responseText: Binding<String>) async throws {
        let request = try makeRequest(messages: messages)
               
        responseBinding = responseText
        
        try await withCheckedThrowingContinuation { continuation in
            streamContinuation = continuation
            
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.dataTask(with: request)
            task.resume()
        }
    }
    
    private func convertRole(_ role: AIChatRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        case .tool: return "tool"
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        
        // Split the response into lines and process each event
        let lines = text.components(separatedBy: "\n")
        for line in lines where line.hasPrefix("data: ") {
            if line == "data: [DONE]" {
                streamContinuation?.resume(returning: ())
                streamContinuation = nil
                return
            }
            
            let jsonStart = line.index(line.startIndex, offsetBy: 6)
            let jsonString = String(line[jsonStart...])
            
            if let data = jsonString.data(using: .utf8),
               let response = try? JSONDecoder().decode(ClaudeStreamResponse.self, from: data)
            {
                if let content = response.delta?.text {
                    DispatchQueue.main.async {
                        self.responseBinding?.wrappedValue += content
                    }
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            streamContinuation?.resume(throwing: error)
        } else if streamContinuation != nil {
            streamContinuation?.resume(returning: ())
        }
        streamContinuation = nil
    }
}

// - MARK: - Stream Response -
struct ClaudeStreamResponse: Codable {
    let type: String
    let delta: Delta?
    
    struct Delta: Codable {
        let text: String?
    }
}
