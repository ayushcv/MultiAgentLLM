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
    @State private var conversationThread: [Message] = []
    @State private var messageQueue: [Message] = []
    @State private var isStreaming = false
    @State private var llmAgents: [LLMRoleAgent] = []
    @State private var mode: String = "host-only"
    @State private var isTerminated = false

    let ollama = OllamaService()
    let CONFIDENCE_THRESHOLD = 0.5
    let CONTEXT_LIMIT = 100

    var body: some View {
        VStack {
            HStack {
                Button("← Back") { onExit() }
                    .padding(.leading)
                Spacer()
                Button("Reset Chat") {
                    chatLog = []
                    conversationThread = []
                    messageQueue = []
                    mode = "host-only"
                    isTerminated = false
                }
                .padding(.trailing)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(chatLog) { msg in
                        HStack(alignment: .top) {
                            Text("🗣 \(msg.role):").bold()
                            Text(msg.content)
                        }
                    }
                }
                .padding()
            }

            if !isTerminated {
                HStack {
                    TextField("Ask the agents...", text: $prompt)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { sendPrompt() }
                }
                .padding()
            } else {
                Text("🔚 Chat has ended. Click Reset Chat to start a new conversation.")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .onAppear {
            if llmAgents.isEmpty {
                llmAgents = agents.map { LLMRoleAgent(role: $0.role, model: $0.selectedModel) }
            }
        }
    }

    func getRelevantContext() -> String {
        let recent = conversationThread.suffix(CONTEXT_LIMIT)
        return recent.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
    }

    func containsMathKeywords(_ text: String) -> Bool {
        let keywords = ["integral", "solve", "equation", "derivative", "limit", "radius", "area", "volume"]
        return keywords.contains { text.lowercased().contains($0) }
    }

    func containsCodeKeywords(_ text: String) -> Bool {
        let keywords = ["function", "bug", "compile", "error", "loop", "code", "variable"]
        return keywords.contains { text.lowercased().contains($0) }
    }

    func moderate(agentMessage: Message) -> Message? {
        let trimmed = agentMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isDuplicate = conversationThread.contains {
            $0.role == agentMessage.role && $0.content == agentMessage.content
        }
        return isDuplicate ? nil : agentMessage
    }

    func evaluateMessageComplexity(_ message: Message, context: [Message], completion: @escaping (String, Double) -> Void) {
        guard let host = llmAgents.first(where: { $0.role.lowercased() == "host" }) else {
            completion("host-only", 0.0)
            return
        }

        let evalPrompt = """
        The user said:
        \"\(message.content)\"

        You are the host of a multi-agent team. If the question relates to code, math, or writing, please delegate by starting your response with the appropriate role mention. For example:
        - For math problems, begin a section with: @Math: [your request to the math agent]
        - For coding challenges, begin a section with: @Coding: [your request to the coding agent]

        After delegating, provide a final summary reply to the user enclosed in quotes only. Do not explain what you are doing, do not reflect.

        Please include in your response a line in the format \"mode: <host-only or initiate-collaboration>\" and \"confidence: <value between 0 and 1>\".
        """

        var fullResponse = ""
        ollama.generateStreamed(prompt: evalPrompt, model: host.model, appendToken: { fullResponse += $0 }) {
            var extractedMode = "host-only"
            var extractedConfidence = 0.0

            if let modeRegex = try? NSRegularExpression(pattern: "mode:\\s*(host-only|initiate-collaboration)"),
               let match = modeRegex.firstMatch(in: fullResponse, range: NSRange(fullResponse.startIndex..., in: fullResponse)),
               let range = Range(match.range(at: 1), in: fullResponse) {
                extractedMode = String(fullResponse[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let confRegex = try? NSRegularExpression(pattern: "confidence:\\s*(0(\\.\\d+)?|1(\\.0)?)"),
               let match = confRegex.firstMatch(in: fullResponse, range: NSRange(fullResponse.startIndex..., in: fullResponse)),
               let range = Range(match.range(at: 1), in: fullResponse) {
                extractedConfidence = Double(String(fullResponse[range]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
            }

            completion(extractedMode, extractedConfidence)
        }
    }

    func finishCollaborative(userMessage: Message, agentReplies: [Message], completion: @escaping () -> Void) {
        guard let host = llmAgents.first(where: { $0.role.lowercased() == "host" }) else {
            completion()
            return
        }

        let summaryPrompt = """
        The user asked: \"\(userMessage.content)\"
        Agents have replied with their insights.

        Please provide a concise final answer to the user, in quotes only. Do not restate the entire conversation or explain what you are doing.
        """

        var hostFinal = ""
        ollama.generateStreamed(prompt: summaryPrompt, model: host.model, appendToken: { hostFinal += $0 }) {
            let pattern = "\\\"(.*?)\\\""
            let summary: String
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: hostFinal, range: NSRange(hostFinal.startIndex..., in: hostFinal)),
               let range = Range(match.range(at: 1), in: hostFinal) {
                summary = String(hostFinal[range])
            } else {
                summary = hostFinal
            }

            let finalMessage = Message(role: host.role, content: summary)
            if let moderated = moderate(agentMessage: finalMessage) {
                chatLog.append(moderated)
                conversationThread.append(moderated)
                messageQueue.append(moderated)
            }
            completion()
        }
    }

    func sendPrompt() {
        guard !isStreaming, !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "end chat" {
            let systemMsg = Message(role: "System", content: "Chat terminated by user.")
            chatLog.append(systemMsg)
            conversationThread.append(systemMsg)
            messageQueue.append(systemMsg)
            isTerminated = true
            prompt = ""
            return
        }

        isStreaming = true
        let userMessage = Message(role: "User", content: prompt)
        chatLog.append(userMessage)
        conversationThread.append(userMessage)
        messageQueue.append(userMessage)

        evaluateMessageComplexity(userMessage, context: conversationThread) { decision, confidence in
            self.mode = confidence < self.CONFIDENCE_THRESHOLD ? "host-only" : decision

            self.handleCollaborative(userMessage: userMessage) {
                self.isStreaming = false
            }
        }

        prompt = ""
    }

    func handleCollaborative(userMessage: Message, completion: @escaping () -> Void) {
        guard let host = llmAgents.first(where: { $0.role.lowercased() == "host" }) else {
            completion()
            return
        }

        var hostDelegationOutput = ""
        let delegationPrompt = """
        The user asked: \"\(userMessage.content)\"
        Relevant context:
        \(getRelevantContext())

        You are the host. Decide if you need to ask @Math, @Coding, etc.
        Write your request for each agent like: @Math: [solve this...]
        If no agents needed, provide a short direct answer.
        """

        ollama.generateStreamed(prompt: delegationPrompt, model: host.model, appendToken: { hostDelegationOutput += $0 }) {
            let pattern = "@([A-Za-z]+):\\s*([\\s\\S]*?)(?=\\n@|$)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                completion()
                return
            }

            let matches = regex.matches(in: hostDelegationOutput, range: NSRange(hostDelegationOutput.startIndex..., in: hostDelegationOutput))
            var updatedDelegationOutput = hostDelegationOutput

            let lowercased = userMessage.content.lowercased()
            if matches.isEmpty {
                if containsMathKeywords(lowercased) {
                    updatedDelegationOutput += "\n\n@Math: Please help solve the following math problem: \"\(userMessage.content)\" using detailed steps."
                } else if containsCodeKeywords(lowercased) {
                    updatedDelegationOutput += "\n\n@Coding: Please help with this coding problem: \"\(userMessage.content)\" and provide a full explanation."
                }
            }

            let newMatches = regex.matches(in: updatedDelegationOutput, range: NSRange(updatedDelegationOutput.startIndex..., in: updatedDelegationOutput))
            var agentReplies: [Message] = []
            let dispatchGroup = DispatchGroup()

            for match in newMatches {
                if match.numberOfRanges >= 3,
                   let roleRange = Range(match.range(at: 1), in: updatedDelegationOutput),
                   let promptRange = Range(match.range(at: 2), in: updatedDelegationOutput) {

                    let roleName = String(updatedDelegationOutput[roleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let agentPrompt = String(updatedDelegationOutput[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                    if let agent = llmAgents.first(where: { $0.role.lowercased() == roleName.lowercased() }) {
                        dispatchGroup.enter()
                        var reply = ""
                        ollama.generateStreamed(prompt: agentPrompt, model: agent.model, appendToken: { reply += $0 }) {
                            let response = Message(role: agent.role, content: reply)
                            if let moderated = moderate(agentMessage: response) {
                                agentReplies.append(moderated)
                            }
                            dispatchGroup.leave()
                        }
                    }
                }
            }

            dispatchGroup.notify(queue: .main) {
                for msg in agentReplies {
                    chatLog.append(msg)
                    conversationThread.append(msg)
                    messageQueue.append(msg)
                }
                finishCollaborative(userMessage: userMessage, agentReplies: agentReplies, completion: completion)
            }
        }
    }
}
