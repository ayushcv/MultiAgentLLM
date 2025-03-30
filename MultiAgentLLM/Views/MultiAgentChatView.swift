import SwiftUI

struct LLMRoleAgent: Identifiable {
    let id = UUID()
    let role: String
    let model: String
    var history: [Message] = []
}

struct MultiAgentChatView: View {
    let agents: [AgentRoleSelection]
    let onExit: () -> Void

    @State private var prompt: String = ""
    @State private var chatLog: [Message] = []
    @State private var isStreaming = false

    let ollama = OllamaService()

    var body: some View {
        VStack {
            HStack {
                Button("← Back") {
                    onExit()
                }
                .padding(.leading)

                Spacer()

                Button("Reset Chat") {
                    chatLog = []
                }
                .padding(.trailing)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(chatLog) { msg in
                        HStack(alignment: .top) {
                            Text("🗣 \(msg.role):")
                                .bold()
                            Text(msg.content)
                        }
                    }
                }
                .padding()
            }

            HStack {
                TextField("Ask the agents...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendPrompt()
                    }
            }
            .padding()
        }
    }

    func sendPrompt() {
        guard !isStreaming, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isStreaming = true

        let userMessage = Message(role: "User", content: prompt)
        chatLog.append(userMessage)

        // Convert AgentRoleSelection into LLMRoleAgent with model access
        let llmAgents = agents.map { agent in
            LLMRoleAgent(role: agent.role, model: agent.selectedModel)
        }

        guard let host = llmAgents.first(where: { $0.role.lowercased() == "host" }) else {
            print("❌ No host agent found")
            isStreaming = false
            return
        }

        let hostPrompt = """
        You are the host in a multi-agent system. The user said:

        \"\(prompt)\"

        If you need help, mention teammates like this:
        @Coding: What function would you use?
        @Math: Explain the equation

        Then finish with a summary later.
        """

        var hostThoughts = ""
        ollama.generateStreamed(prompt: hostPrompt, model: host.model, appendToken: { token in
            hostThoughts += token
        }, completion: {
            let thinkingMessage = Message(role: host.role, content: hostThoughts)
            chatLog.append(thinkingMessage)

            let pattern = #"@(\w+):([\s\S]*?)(?=@\w+:|$)"#
            let regex = try! NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: hostThoughts, range: NSRange(hostThoughts.startIndex..., in: hostThoughts))

            var agentReplies: [String: String] = [:]
            let dispatchGroup = DispatchGroup()

            for match in matches {
                let roleRange = Range(match.range(at: 1), in: hostThoughts)!
                let promptRange = Range(match.range(at: 2), in: hostThoughts)!
                let role = String(hostThoughts[roleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let agentPrompt = String(hostThoughts[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                guard !agentPrompt.isEmpty else { continue }

                if let agent = llmAgents.first(where: { $0.role.lowercased() == role.lowercased() }) {
                    print("📨 Routing to \(agent.role): \(agentPrompt)")
                    dispatchGroup.enter()

                    var reply = ""
                    ollama.generateStreamed(prompt: agentPrompt, model: agent.model, appendToken: { token in
                        reply += token
                    }, completion: {
                        agentReplies[role] = reply
                        let agentMessage = Message(role: role, content: reply)
                        chatLog.append(agentMessage)
                        dispatchGroup.leave()
                    })
                } else {
                    print("⚠️ Agent with role \(role) not found.")
                }
            }

            dispatchGroup.notify(queue: .main) {
                let finalPrompt = """
                The user said:
                \"\(prompt)\"

                Your teammates responded:
                \(agentReplies.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))

                Now write a final reply to the user.
                """

                var finalResponse = ""
                ollama.generateStreamed(prompt: finalPrompt, model: host.model, appendToken: { token in
                    finalResponse += token
                }, completion: {
                    let finalMsg = Message(role: host.role, content: finalResponse)
                    chatLog.append(finalMsg)
                    isStreaming = false
                })
            }
        })

        prompt = ""
    }
}
