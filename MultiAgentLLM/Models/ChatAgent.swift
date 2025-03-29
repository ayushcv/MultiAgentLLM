import Foundation

class ChatAgent: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let systemPrompt: String
    @Published var history: [Message] = []

    init(name: String, model: String, systemPrompt: String) {
        self.name = name
        self.model = model
        self.systemPrompt = systemPrompt
    }
}
