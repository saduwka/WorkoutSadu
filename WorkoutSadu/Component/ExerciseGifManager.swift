import Foundation

final class ExerciseGifManager: Sendable {
    static let shared = ExerciseGifManager()

    private let cacheDir: URL
    private let memory = NSCache<NSString, NSData>()

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("exercise_gifs", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 40
    }

    func cachedGif(for url: String) -> Data? {
        let key = cacheKey(url)
        if let d = memory.object(forKey: key as NSString) { return d as Data }
        let file = cacheDir.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: file.path),
              let d = try? Data(contentsOf: file) else { return nil }
        memory.setObject(d as NSData, forKey: key as NSString)
        return d
    }

    func loadGif(from url: String) async -> Data? {
        if let cached = cachedGif(for: url) {
            print("[GifCache] ✅ Cache hit: \(url.suffix(30))")
            return cached
        }

        guard let remote = URL(string: url) else {
            print("[GifCache] ❌ Invalid URL: \(url)")
            return nil
        }
        do {
            print("[GifCache] ⬇️ Downloading: \(url)")
            var request = URLRequest(url: remote)
            if url.contains("exercisedb") || url.contains("rapidapi") {
                request.setValue(ExerciseDBService.apiKey, forHTTPHeaderField: "x-rapidapi-key")
                request.setValue("exercisedb.p.rapidapi.com", forHTTPHeaderField: "x-rapidapi-host")
            }
            let (data, resp) = try await URLSession.shared.data(for: request)
            let http = resp as? HTTPURLResponse
            let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            print("[GifCache] 📡 Status: \(http?.statusCode ?? -1), Content-Type: \(contentType), Size: \(data.count) bytes")
            
            if let http, http.statusCode == 301 || http.statusCode == 302 {
                let location = http.value(forHTTPHeaderField: "Location") ?? "none"
                print("[GifCache] 🔀 Redirect to: \(location)")
            }
            
            guard let http, http.statusCode == 200 else {
                print("[GifCache] ❌ Bad status, body: \(String(data: data.prefix(200), encoding: .utf8) ?? "non-utf8")")
                return nil
            }
            
            let key = cacheKey(url)
            let file = cacheDir.appendingPathComponent(key)
            try? data.write(to: file)
            memory.setObject(data as NSData, forKey: key as NSString)
            print("[GifCache] ✅ Saved \(data.count) bytes")
            return data
        } catch {
            print("[GifCache] ❌ Download error: \(error)")
            return nil
        }
    }

    func removeGif(for url: String) {
        let key = cacheKey(url)
        memory.removeObject(forKey: key as NSString)
        let file = cacheDir.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: file)
    }

    private func cacheKey(_ url: String) -> String {
        var hash: UInt64 = 5381
        for byte in url.utf8 { hash = 127 &* hash &+ UInt64(byte) }
        return "\(hash).gif"
    }
}
