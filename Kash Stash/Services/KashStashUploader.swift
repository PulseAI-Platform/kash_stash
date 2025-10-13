import Foundation

struct UploadPayload: Codable {
    struct File: Codable {
        let content: String
        let filename: String
        let content_type: String
        let context_prompt: String
    }
    let file: File
    let tags: String
    let device: String
    // context_prompt is only used for photos, ignored on notes
}

class KashStashUploader {

    /// Combines user tags and device name (if not empty and not already present) into a comma-separated tag list.
    private static func mergedTags(userTags: String, deviceName: String) -> String {
        let userTagsArr = userTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let deviceTag = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        var tagsSet = Set(userTagsArr.map { String($0) })
        if !deviceTag.isEmpty {
            tagsSet.insert(deviceTag)
        }
        return tagsSet.joined(separator: ",")
    }

    static func uploadTextNote(
        text: String,
        tags: String,
        endpoint: KashStashEndpoint,
        completion: @escaping (Bool) -> Void
    ) {
        let filename = "note_\(Int(Date().timeIntervalSince1970)).txt"
        let fileData = text.data(using: .utf8)!
        let fullTags = mergedTags(userTags: tags, deviceName: endpoint.device)
        let payload: [String: Any] = [
            "file": [
                "content": fileData.base64EncodedString(),
                "filename": filename,
                "content_type": "text/plain"
            ],
            "tags": fullTags,
            "device": endpoint.device
        ]
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else { completion(false); return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.probeKey, forHTTPHeaderField: "X-PROBE-KEY")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
}

extension KashStashUploader {
    static func uploadPhoto(
        data: Data,
        tags: String,
        context: String,
        endpoint: KashStashEndpoint,
        completion: @escaping (Bool) -> Void
    ) {
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let fullTags = mergedTags(userTags: tags, deviceName: endpoint.device)
        let payload = UploadPayload(
            file: .init(
                content: data.base64EncodedString(),
                filename: filename,
                content_type: "image/png",
                context_prompt: context
            ),
            tags: fullTags,
            device: endpoint.device
        )
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else { completion(false); return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.probeKey, forHTTPHeaderField: "X-PROBE-KEY")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
}
