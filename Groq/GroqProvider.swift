import SwiftUI

class GroqProvider: NSObject, AIServiceProvider {
    private var apiKey: String { AIProvider.groq.apiKey }
    private var model = "mixtral-8x7b-32768" // or "llama2-70b-4096"

    internal var models: [String] = [
        "mixtral-8x7b-32768",
        "llama2-70b-4096",
        "llama-3.3-70b-versatile"
        ]
    
    func setModel(_ newModel: String) {
        model = newModel
    }

    func makeRequest(messages: [AIChatMessage], stream: Bool = true) throws -> URLRequest {
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { [
                "role": $0.role.rawValue,
                "content": $0.content
            ] },
            "stream": stream
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func execute(messages: [AIChatMessage]) async throws -> String {
        do {
            let request = try makeRequest(messages: messages, stream: false)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            return response.choices.first?.message.content ?? ""

        } catch let DecodingError.dataCorrupted(context) {
            print(context)
        } catch let DecodingError.keyNotFound(key, context) {
            print("Key '\(key)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.valueNotFound(value, context) {
            print("Value '\(value)' not found:", context.debugDescription)
            print("codingPath:", context.codingPath)
        } catch let DecodingError.typeMismatch(type, context) {
            print("Type '\(type)' mismatch:", context.debugDescription)
            print("codingPath:", context.codingPath)

        } catch {
            print("Error decoding JSON: \(error)")
        }
        return "Error decoding or requesting the data"
    }

    func executeStream(messages: [AIChatMessage], responseText: Binding<String>) async throws {
        let request = try makeRequest(messages: messages)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = StreamDelegate(responseText: responseText) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: request)
            task.resume()
        }
    }
}

// StreamDelegate implementation (same as OpenAI since GROQ uses compatible format)
private class StreamDelegate: NSObject, URLSessionDataDelegate {
    private var responseText: Binding<String>
    private var completion: (Error?) -> Void
    private var receivedResponse = false

    init(responseText: Binding<String>, completion: @escaping (Error?) -> Void) {
        self.responseText = responseText
        self.completion = completion
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            receivedResponse = true
            completionHandler(.allow)
        } else {
            completion(URLError(.badServerResponse))
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        let lines = string.components(separatedBy: "\n")
        for line in lines where line.hasPrefix("data: ") {
            let json = line.replacingOccurrences(of: "data: ", with: "")
            if json == "[DONE]" {
                completion(nil)
                return
            }
            processJSON(json)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion(error)
        } else if !receivedResponse {
            completion(URLError(.badServerResponse))
        }
    }

    private func processJSON(_ json: String) {
        guard let data = json.data(using: .utf8) else { return }
        do {
            let response = try JSONDecoder().decode(OpenAIStreamResponse.self, from: data)
            if let content = response.choices.first?.delta.content {
                DispatchQueue.main.async {
                    self.responseText.wrappedValue += content
                }
            }
        } catch {
            print("Error decoding JSON: \(error)")
        }
    }
}
