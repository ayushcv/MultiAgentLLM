// OllamaService.swift
import Foundation

class OllamaService {
    func generateStreamed(prompt: String, model: String, appendToken: @escaping (String) -> Void, completion: @escaping () -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": true
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("Streaming error:", error)
                return
            }

            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                print("Invalid response from Ollama")
                return
            }

            // Parse line-by-line streamed JSON
            text.enumerateLines { line, _ in
                if let jsonData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let token = json["response"] as? String {
                    DispatchQueue.main.async {
                        appendToken(token)
                    }
                }
            }

            DispatchQueue.main.async {
                completion()
            }
        }

        task.resume()
    }
}
