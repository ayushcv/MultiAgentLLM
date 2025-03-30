// OllamaService.swift
import Foundation

class OllamaService {
    func generateStreamed(
        prompt: String,
        model: String,
        appendToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
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

    func fetchInstalledModels(completion: @escaping ([String]) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion([])
            return
        }

        let request = URLRequest(url: url)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("Model fetch error:", error)
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["models"] as? [[String: Any]] else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            let names = models.compactMap { $0["name"] as? String }
            DispatchQueue.main.async {
                completion(names)
            }
        }.resume()
    }
}
