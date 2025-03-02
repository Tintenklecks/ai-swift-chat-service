import Foundation
import SwiftUI

class AIChatService: ObservableObject {
    private var service: AIServiceProvider
    private var provider: AIProvider // openai, claude, gemini, groq
    
    @Published public private(set) var messages: [AIChatMessage] = []
    @Published private(set) var state: AIChatServiceState = .idle
    @Published private(set) var response: String = ""
    
    init(_ provider: AIProvider = .openAI) {
        self.provider = provider
        self.service = provider.provider
        
    }
        
    // MARK: - Provider methods -

    func setProvider(_ provider: AIProvider) {
        self.provider = provider
        service = provider.provider
    }
    
    func setModel(_ newModel: String) {
        service.setModel(newModel)
    }
    
    func setModel(_ newModel: Int) throws {
        if newModel >= 0 && newModel < service.models.count {
            
            setModel(service.models[newModel])
        }
        else {
            throw NSError(domain: "Invalid model index", code: 0)
        }
            
    }
    
    func addMessage(_ message: AIChatMessage) {
        messages.append(message)
    }
    
    func addAIMessage(_ message: String) {
        addMessage(AIChatMessage(role: .assistant, content: message))
    }
    
    func addUserMessage(_ message: String) {
        addMessage(AIChatMessage(role: .user, content: message))
    }
    
    func setSystemMessage(_ message: String) {
        let systemMessage = AIChatMessage(role: .system, content: message)
        if let firstMessage = messages.first, firstMessage.role == .system {
            messages[0] = systemMessage
        } else {
            messages.insert(systemMessage, at: 0)
        }
    }
    
    func setMessages(_ newMessages: [AIChatMessage]) {
        messages = newMessages
    }
    
    func reset() {
        messages.removeAll()
        state = .idle
    }
    
    func execute(responseText: Binding<String>) {
        state = .active
        Task { @MainActor in
            
            do {
                try await service.executeStream(messages: messages, responseText: responseText)
                service.handleStreamCompletion(responseText: responseText.wrappedValue) { message in
                    self.messages.append(message)
                }
                state = .done
                responseText.wrappedValue = ""
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    func execute(addChunk: @escaping (String) -> ()) {
        state = .active
        Task { @MainActor in
            do {
                var x: String = ""
                let binding = Binding<String>(
                    get: { x },
                    set: { newValue in
                        x += newValue
                        // Only send the incremental chunk
                        print(newValue)
                        let chunk = newValue
                        if !chunk.isEmpty {
                            addChunk(chunk)
                        }
                    }
                )
                
                try await service.executeStream(messages: messages, responseText: binding)
                response = binding.wrappedValue
                self.addAIMessage(response)
                
//                service
//                    .handleStreamCompletion(
//                        responseText: binding.wrappedValue
//                    ) { message in
//                    self.messages.append(message)
//                }
                state = .done
                response = ""
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    func execute() async throws -> String {
        state = .active
        response = ""

        do {
            let result = try await service.execute(messages: messages)
            await MainActor.run {
                addAIMessage(result)
                state = .done
            }
            return result
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }
}
