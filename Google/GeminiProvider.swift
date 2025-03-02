import SwiftUI

class GeminiProvider: NSObject, AIServiceProvider, URLSessionDataDelegate {
    internal var models: [String] = ["gemini-1.5-flash-8b", "gemini-2.0-flash-exp", "gemini-1.5-pro"]
    private var model = "gemini-1.5-flash-8b"

    private var apiKey: String { AIProvider.gemini.apiKey }
    private var streamContinuation: CheckedContinuation<Void, Error>?
    private var responseBinding: Binding<String>?
    
    func setModel(_ newModel: String) {
        model = newModel
    }
    
    func makeRequest(messages: [AIChatMessage], stream: Bool = true) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1/models/\(model)\(stream ? ":streamGenerateContent" : ":generateContent")?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert messages to Gemini 2.0 format
        let contents = messages.map { message in
            [
                "role": convertRole(message.role),
                "parts": [
                    [
                        "text": message.content
                    ]
                ]
            ]
        }
        
        let body: [String: Any] = [
            "contents": contents,
            "safety_settings": [
                [
                    "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                    "threshold": "BLOCK_ONLY_HIGH"
                ],
                [
                    "category": "HARM_CATEGORY_HARASSMENT",
                    "threshold": "BLOCK_ONLY_HIGH"
                ],
                [
                    "category": "HARM_CATEGORY_HATE_SPEECH",
                    "threshold": "BLOCK_ONLY_HIGH"
                ],
                [
                    "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                    "threshold": "BLOCK_ONLY_HIGH"
                ]
            ],
            "generation_config": [
                "temperature": 0.7,
                "topP": 0.8,
                "topK": 40,
                "maxOutputTokens": 2048,
                "stopSequences": []
            ]
        ]
        
        // Debug print the request body
        if let jsonData = try? JSONSerialization.data(withJSONObject: body, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print("Request body: \(jsonString)")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func execute(messages: [AIChatMessage]) async throws -> String {
        let request = try makeRequest(messages: messages, stream: false)
        let (data, _) = try await URLSession.shared.data(for: request)
        responseBinding?.wrappedValue = ""

        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        
        if let error = response.error {
            throw error
        }
        
        guard let content = response.candidates?.first?.content.parts.first?.text else {
            throw GeminiError(message: "No content in response", code: 500, status: "INVALID_RESPONSE")
        }
        
        return content
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
        case .assistant: return "model"
        case .system: return "user"
        case .tool: return "model"
        }
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let cleanedText = text.trimmingCharacters(in: CharacterSet(charactersIn: ",[]"))
        
        do {
            if let jsonData = cleanedText.data(using: .utf8) {
                let response = try JSONDecoder().decode(GeminiStreamResponse.self, from: jsonData)
                
                if let error = response.error {
                    print("Gemini API Error: \(error.message)")
                    if let continuation = streamContinuation {
                        streamContinuation = nil
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                if let candidate = response.candidates?.first {
                    if let content = candidate.content?.parts.first?.text {
                        DispatchQueue.main.async {
                            self.responseBinding?.wrappedValue += content
                        }
                    } else if candidate.finishReason == "SAFETY" {
                        let error = GeminiError(
                            message: "Content blocked due to safety concerns",
                            code: 400,
                            status: "SAFETY_BLOCK"
                        )
                        if let continuation = streamContinuation {
                            streamContinuation = nil
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } catch {
            if !cleanedText.isEmpty {
                print("Error processing Gemini response: \(error)")
                print("Raw response: \(cleanedText)")
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Only call resume if we still have a continuation
        if let continuation = streamContinuation {
            streamContinuation = nil
            if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: ())
            }
        }
    }
}

// - MARK: - Stream Response -

// Updated Gemini response structures for v2.0
struct GeminiStreamResponse: Codable {
    let candidates: [Candidate]?
    let error: GeminiError?
    let usageMetadata: UsageMetadata?
    let modelVersion: String?
    
    struct Candidate: Codable {
        let content: Content?  // Make optional since it might not be present
        let finishReason: String?
        let index: Int
        let safetyRatings: [SafetyRating]?
        
        enum CodingKeys: String, CodingKey {
            case content
            case finishReason = "finish_reason"
            case index
            case safetyRatings
        }
    }
    
    struct Content: Codable {
        let parts: [Part]
        let role: String
    }
    
    struct Part: Codable {
        let text: String
    }
    
    struct SafetyRating: Codable {
        let category: String
        let probability: String
    }
    
    struct UsageMetadata: Codable {
        let promptTokenCount: Int
        let totalTokenCount: Int
    }
}

// Add these structures for error handling
struct GeminiErrorResponse: Codable {
    let error: GeminiError
}

struct GeminiError: Error, Codable {
    let message: String
    var code: Int?
    var status: String?
}

// Add this structure for non-streaming responses
struct GeminiResponse: Codable {
    let candidates: [Candidate]?
    let error: GeminiError?
    
    struct Candidate: Codable {
        let content: Content
        let finishReason: String?
        let index: Int
        let safetyRatings: [SafetyRating]?
        
        enum CodingKeys: String, CodingKey {
            case content
            case finishReason = "finish_reason"
            case index
            case safetyRatings
        }
    }
    
    struct Content: Codable {
        let parts: [Part]
        let role: String
    }
    
    struct Part: Codable {
        let text: String
    }
    
    struct SafetyRating: Codable {
        let category: String
        let probability: String
    }
}
