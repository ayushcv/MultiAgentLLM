import SwiftUI

struct ContentView: View {
    @StateObject private var currentAgent = ChatAgent(
        name: "Writer",
        model: "llama2",
        systemPrompt: "You are a helpful writing assistant."
    )
    @State private var prompt: String = ""
    @State private var currentStreamingMessage = ""
    @State private var installedModels: [String] = []
    @State private var selectedModel: String = "llama2"
    @State private var isStreaming = false

    let ollama = OllamaService()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Agent: \(currentAgent.name)")
                Spacer()
                Button("Clear") {
                    currentAgent.history.removeAll()
                }
            }
            .padding(.horizontal)

            Picker("Select Model", selection: $selectedModel) {
                ForEach(installedModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .onChange(of: selectedModel) {
                currentAgent.model = selectedModel
            }
            .padding(.horizontal)
            .onAppear {
                ollama.fetchInstalledModels { models in
                    self.installedModels = models
                    if !models.contains(currentAgent.model) {
                        currentAgent.model = models.first ?? "llama2"
                        selectedModel = currentAgent.model
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(currentAgent.history) { msg in
                            HStack(alignment: .top) {
                                Text(msg.role == "user" ? "🧑‍💻 You:" : "🤖 AI:")
                                    .bold()
                                Text(msg.content)
                            }
                        }
                        if !currentStreamingMessage.isEmpty {
                            HStack(alignment: .top) {
                                Text("🤖 AI:")
                                    .bold()
                                Text(currentStreamingMessage)
                            }
                        }
                    }
                    .padding()
                }
            }

            HStack {
                TextField("Enter prompt", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendPrompt()
                    }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 550)
    }

    func sendPrompt() {
        guard !isStreaming else { return }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isStreaming = true
        let userMessage = Message(role: "user", content: prompt)
        currentAgent.history.append(userMessage)
        currentStreamingMessage = ""
        var fullResponse = ""

        let fullPrompt = buildPromptWithContext()

        ollama.generateStreamed(
            prompt: fullPrompt,
            model: currentAgent.model,
            appendToken: { token in
                fullResponse += token
                currentStreamingMessage = fullResponse
            },
            completion: {
                let aiMessage = Message(role: "assistant", content: fullResponse)
                currentAgent.history.append(aiMessage)
                currentStreamingMessage = ""
                isStreaming = false
            }
        )

        prompt = ""
    }

    func buildPromptWithContext() -> String {
        var combined = currentAgent.systemPrompt + "\n\n"
        let historyLimit = 10

        let recentMessages = currentAgent.history.suffix(historyLimit)

        for message in recentMessages {
            if message.role == "user" {
                combined += "User: \(message.content)\n"
            } else if message.role == "assistant" {
                combined += "AI: \(message.content)\n"
            }
        }

        combined += "AI:"
        return combined
    }
}
