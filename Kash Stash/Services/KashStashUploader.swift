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
}

class KashStashUploader {
    
    // MARK: - Private Helpers
    
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
    
    // MARK: - Original Upload Methods
    
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
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else {
            completion(false)
            return
        }
        
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
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else {
            completion(false)
            return
        }
        
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
    
    // MARK: - New Upload Methods
    
    static func uploadFile(
        data: Data,
        filename: String,
        mimeType: String,
        tags: String,
        endpoint: KashStashEndpoint,
        completion: @escaping (Bool) -> Void
    ) {
        let fullTags = mergedTags(userTags: tags, deviceName: endpoint.device)
        let payload: [String: Any] = [
            "file": [
                "content": data.base64EncodedString(),
                "filename": filename,
                "content_type": mimeType
            ],
            "tags": fullTags,
            "device": endpoint.device
        ]
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else {
            completion(false)
            return
        }
        
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
    
    static func uploadWithDestination(
        data: Data,
        filename: String,
        mimeType: String,
        tags: String,
        context: String,
        destination: UploadDestination,
        endpoint: KashStashEndpoint?,
        kashFiles: KashFilesConfig?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        print("[Upload] Starting upload - Destination: \(destination.rawValue)")
        print("[Upload] Endpoint: \(endpoint?.name ?? "none"), KashFiles: \(kashFiles?.name ?? "none")")
        
        switch destination {
        case .endpointOnly:
            guard let endpoint = endpoint else {
                completion(false, "No endpoint configured")
                return
            }
            
            if mimeType.hasPrefix("image/") {
                uploadPhoto(data: data, tags: tags, context: context, endpoint: endpoint) { success in
                    completion(success, nil)
                }
            } else {
                uploadFile(data: data, filename: filename, mimeType: mimeType, tags: tags, endpoint: endpoint) { success in
                    completion(success, nil)
                }
            }
            
        case .kashFilesOnly:
            guard let kashFiles = kashFiles else {
                print("[Upload] ERROR: No Kash Files configured")
                completion(false, "No Kash Files configured")
                return
            }
            
            print("[Upload] Starting Kash Files upload to: \(kashFiles.baseURL)")
            
            KashFilesClient.uploadFile(data: data, filename: filename, mimeType: mimeType, config: kashFiles) { result in
                switch result {
                case .success(let response):
                    print("[Upload] Kash Files upload successful")
                    
                    // Build the full download URL from the response
                    var downloadURL: String
                    if let download = response.download {
                        // Use the download path from response
                        downloadURL = "\(kashFiles.baseURL)\(download)"
                    } else if let location = response.location {
                        // Fallback to location
                        downloadURL = "\(kashFiles.baseURL)/api/files/\(location)"
                    } else {
                        // Last resort
                        downloadURL = "\(kashFiles.baseURL)/files/\(filename)"
                    }
                    
                    print("[Upload] Download URL: \(downloadURL)")
                    
                    // If we have an endpoint, create a link digest
                    if let endpoint = endpoint {
                        let linkNote = "📎 File uploaded to Kash Files: \(response.filename ?? filename)\n\nAccess URL: \(downloadURL)"
                        let linkTags = "\(tags),kash-files-link,\(filename)"
                        
                        uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { success in
                            print("[Upload] Link digest creation: \(success ? "success" : "failed")")
                            completion(true, downloadURL)
                        }
                    } else {
                        completion(true, downloadURL)
                    }
                case .failure(let error):
                    print("[Upload] Kash Files upload failed: \(error)")
                    completion(false, error.localizedDescription)
                }
            }
            
        case .both:
            guard let endpoint = endpoint, let kashFiles = kashFiles else {
                completion(false, "Both endpoint and Kash Files required")
                return
            }
            
            print("[Upload] Starting BOTH mode upload")
            
            // First upload to Kash Files
            KashFilesClient.uploadFile(data: data, filename: filename, mimeType: mimeType, config: kashFiles) { result in
                switch result {
                case .success(let response):
                    print("[Upload] Kash Files upload successful in BOTH mode")
                    
                    // Build the full download URL from the response
                    var downloadURL: String
                    if let download = response.download {
                        downloadURL = "\(kashFiles.baseURL)\(download)"
                    } else if let location = response.location {
                        downloadURL = "\(kashFiles.baseURL)/api/files/\(location)"
                    } else {
                        downloadURL = "\(kashFiles.baseURL)/files/\(filename)"
                    }
                    
                    if mimeType.hasPrefix("image/") {
                        // IMAGES: Two separate digests (existing behavior)
                        uploadPhoto(data: data, tags: "\(tags),\(filename)", context: context, endpoint: endpoint) { photoSuccess in
                            if photoSuccess {
                                print("[Upload] Image digest created successfully")
                                let linkNote = "🖼️ Image in Kash Files: \(response.filename ?? filename)\n\nDirect URL: \(downloadURL)"
                                let linkTags = "\(tags),kash-files-link,image-link,\(filename)"
                                
                                uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { linkSuccess in
                                    print("[Upload] Link digest creation: \(linkSuccess ? "success" : "failed")")
                                    completion(photoSuccess && linkSuccess, downloadURL)
                                }
                            } else {
                                print("[Upload] Failed to create image digest")
                                completion(false, "Failed to create image digest")
                            }
                        }
                    } else if mimeType == "text/plain" {
                        // TEXT NOTES: Single digest with user content + link
                        // Get the original text content
                        let originalText = String(data: data, encoding: .utf8) ?? ""
                        
                        // Create a combined note with user's text and the file link
                        let combinedNote = """
                        \(originalText)
                        
                        File: \(response.filename ?? filename)
                        Link: \(downloadURL)
                        """
                        
                        // Upload as a single digest with the combined content
                        uploadTextNote(text: combinedNote, tags: tags, endpoint: endpoint) { success in
                            print("[Upload] Combined note+link digest creation: \(success ? "success" : "failed")")
                            completion(success, downloadURL)
                        }
                    } else {
                        // OTHER FILES: Just create link digest
                        let linkNote = "📎 File in Kash Files: \(response.filename ?? filename)\n\nAccess URL: \(downloadURL)"
                        let linkTags = "\(tags),kash-files-link,\(filename)"
                        
                        uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { linkSuccess in
                            print("[Upload] Link digest creation: \(linkSuccess ? "success" : "failed")")
                            completion(linkSuccess, downloadURL)
                        }
                    }
                case .failure(let error):
                    print("[Upload] Kash Files upload failed in BOTH mode: \(error)")
                    completion(false, "Kash Files upload failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
