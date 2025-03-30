//
//  AgentModelSelectorView.swift
//  MultiAgentLLM
//
//  Created by Ayush Singh on 2025-03-29.
//

import SwiftUI

struct AgentRoleSelection: Identifiable {
    let id = UUID()
    let role: String
    var selectedModel: String
}

struct AgentModelSelectorView: View {
    @State private var availableModels: [String] = []
    @State private var agentRoles: [AgentRoleSelection] = []
    @State private var showChat = false
    let ollama = OllamaService()

    var body: some View {
        if showChat {
            MultiAgentChatView(agents: agentRoles, onExit: {
                self.showChat = false
            })
        } else {
            VStack(spacing: 20) {
                Text("Select LLMs for Each Role")
                    .font(.title2)
                    .padding(.top)

                ForEach($agentRoles) { $agent in
                    HStack {
                        Text(agent.role + ":")
                            .bold()
                            .frame(width: 80, alignment: .leading)
                        Picker("Select Model", selection: $agent.selectedModel) {
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }

                Button("Start Chat") {
                    showChat = true
                }
                .disabled(!allAgentsConfigured)
                .padding(.top)

                Spacer()
            }
            .padding()
            .onAppear {
                ollama.fetchInstalledModels { models in
                    self.availableModels = models
                    if self.agentRoles.isEmpty {
                        self.agentRoles = [
                            AgentRoleSelection(role: "Host", selectedModel: models.first ?? ""),
                            AgentRoleSelection(role: "Coding", selectedModel: models.first ?? ""),
                            AgentRoleSelection(role: "Math", selectedModel: models.first ?? "")
                        ]
                    }
                }
            }
        }
    }

    var allAgentsConfigured: Bool {
        agentRoles.allSatisfy { !$0.selectedModel.isEmpty }
    }
}


