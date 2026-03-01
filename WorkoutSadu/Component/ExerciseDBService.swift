import Foundation

struct ExerciseDBItem: Identifiable, Decodable {
    let id: String
    let name: String
    let bodyPart: String
    let equipment: String
    let target: String
    let secondaryMuscles: [String]?
    let instructions: [String]?

    var gifUrl: String {
        "https://exercisedb.p.rapidapi.com/image?exerciseId=\(id)&resolution=360"
    }
}

final class ExerciseDBService {
    static let shared = ExerciseDBService()

    // ← Вставь свой API-ключ от RapidAPI сюда
    static var apiKey: String = "a6ae048f29msh4082b47d999bc49p1e1985jsn29847a566322"

    private let host = "exercisedb.p.rapidapi.com"
    private let baseURL = "https://exercisedb.p.rapidapi.com"

    private init() {}

    func search(query: String) async throws -> [ExerciseDBItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let url = URL(string: "\(baseURL)/exercises/name/\(encoded)?offset=0&limit=20")!

        print("[ExerciseDB] 🔍 Search: \(url.absoluteString)")
        print("[ExerciseDB] 🔑 API Key: \(Self.apiKey.prefix(8))...")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(host, forHTTPHeaderField: "x-rapidapi-host")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        print("[ExerciseDB] 📡 Status: \(http?.statusCode ?? -1)")
        print("[ExerciseDB] 📦 Body (\(data.count) bytes): \(String(data: data.prefix(500), encoding: .utf8) ?? "non-utf8")")

        guard let http, http.statusCode == 200 else {
            throw ExerciseDBError.badStatus(http?.statusCode ?? -1, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let first = json.first {
            print("[ExerciseDB] 🗝️ Keys: \(first.keys.sorted())")
            for (k, v) in first where k.lowercased().contains("gif") || k.lowercased().contains("url") || k.lowercased().contains("image") {
                print("[ExerciseDB] 📎 \(k) = \(v)")
            }
        }

        do {
            let items = try JSONDecoder().decode([ExerciseDBItem].self, from: data)
            print("[ExerciseDB] ✅ Decoded \(items.count) items")
            return items
        } catch {
            print("[ExerciseDB] ❌ Decode error: \(error)")
            throw error
        }
    }

    func fetchByBodyPart(_ part: String) async throws -> [ExerciseDBItem] {
        let encoded = part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? part
        let url = URL(string: "\(baseURL)/exercises/bodyPart/\(encoded)?offset=0&limit=30")!

        print("[ExerciseDB] 🔍 BodyPart: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue(host, forHTTPHeaderField: "x-rapidapi-host")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        print("[ExerciseDB] 📡 Status: \(http?.statusCode ?? -1)")
        print("[ExerciseDB] 📦 Body (\(data.count) bytes): \(String(data: data.prefix(500), encoding: .utf8) ?? "non-utf8")")

        guard let http, http.statusCode == 200 else {
            throw ExerciseDBError.badStatus(http?.statusCode ?? -1, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        do {
            let items = try JSONDecoder().decode([ExerciseDBItem].self, from: data)
            print("[ExerciseDB] ✅ Decoded \(items.count) items")
            return items
        } catch {
            print("[ExerciseDB] ❌ Decode error: \(error)")
            throw error
        }
    }

    enum ExerciseDBError: LocalizedError {
        case badStatus(Int, String)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                return "HTTP \(code): \(body.prefix(150))"
            }
        }
    }
}
