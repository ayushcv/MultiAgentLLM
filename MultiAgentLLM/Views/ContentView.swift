import SwiftUI

struct ContentView: View {
    @StateObject private var currentAgent = ChatAgent(name: "Writer", model: "llama2", systemPrompt: "You are a helpful writing assistant.")
    @State private var prompt: String = ""
    @State private var currentStreamingMessage = ""
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

                Button("Send") {
                    let userMessage = Message(role: "user", content: prompt)
                    currentAgent.history.append(userMessage)
                    currentStreamingMessage = ""
                    var fullResponse = ""

                    ollama.generateStreamed(prompt: prompt, model: currentAgent.model, appendToken: { token in
                        fullResponse += token
                        currentStreamingMessage = fullResponse
                    }, completion: {
                        let aiMessage = Message(role: "assistant", content: fullResponse)
                        currentAgent.history.append(aiMessage)
                        currentStreamingMessage = ""
                    })

                    prompt = ""
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}
