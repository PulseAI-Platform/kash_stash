import Foundation

// MARK: - Upload Size Limit
let MAX_UPLOAD_SIZE_BYTES: Int = 100 * 1024 * 1024 // 100 MB

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
            tagsSet.insert("from-\(deviceTag)")
        }
        
        return tagsSet.joined(separator: ",")
    }
    
    /// Check if data exceeds the upload limit
    static func checkSizeLimit(_ data: Data) -> (allowed: Bool, message: String?) {
        if data.count > MAX_UPLOAD_SIZE_BYTES {
            let sizeMB = Double(data.count) / (1024 * 1024)
            return (false, String(format: "File size (%.1f MB) exceeds the 100 MB upload limit.", sizeMB))
        }
        return (true, nil)
    }
    
    // MARK: - Text Note Upload
    
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
        request.timeoutInterval = 60
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                print("[Upload] Text note timed out")
                DispatchQueue.main.async { completion(false) }
                return
            }
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
    
    // MARK: - Photo Upload (with AI context)
    
    static func uploadPhoto(
        data: Data,
        tags: String,
        context: String,
        endpoint: KashStashEndpoint,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let filename = "screenshot_\(Int(Date().timeIntervalSince1970)).png"
        let fullTags = mergedTags(userTags: tags, deviceName: endpoint.device)
        
        // CRITICAL: context_prompt MUST be at TOP LEVEL, not inside file object
        let payload: [String: Any] = [
            "file": [
                "content": data.base64EncodedString(),
                "filename": filename,
                "content_type": "image/png"
            ],
            "tags": fullTags,
            "device": endpoint.device,
            "context_prompt": context
        ]
        
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.probeKey, forHTTPHeaderField: "X-PROBE-KEY")
        request.timeoutInterval = 120
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                print("[Upload] Photo upload timed out")
                DispatchQueue.main.async {
                    completion(false, "Long-running request or possible timeout - check Pulse in a few minutes to see if processing completed.")
                }
                return
            }
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success, success ? nil : "Upload failed") }
        }.resume()
    }
    
    // MARK: - Generic File Upload (for ingestion API)
    
    static func uploadFile(
        data: Data,
        filename: String,
        mimeType: String,
        tags: String,
        endpoint: KashStashEndpoint,
        contextPrompt: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let fullTags = mergedTags(userTags: tags, deviceName: endpoint.device)
        
        var payload: [String: Any] = [
            "file": [
                "content": data.base64EncodedString(),
                "filename": filename,
                "content_type": mimeType
            ],
            "tags": fullTags,
            "device": endpoint.device
        ]
        
        // Add context_prompt at top level if provided
        if let ctx = contextPrompt, !ctx.isEmpty {
            payload["context_prompt"] = ctx
        }
        
        guard let url = URL(string: "https://probes-\(endpoint.nodeName).xyzpulseinfra.com/api/probes/\(endpoint.probeId)/run") else {
            completion(false, "Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.probeKey, forHTTPHeaderField: "X-PROBE-KEY")
        request.timeoutInterval = 180
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error as NSError?, error.code == NSURLErrorTimedOut {
                print("[Upload] File upload timed out")
                DispatchQueue.main.async {
                    completion(false, "Long-running request or possible timeout - check Pulse in a few minutes to see if processing completed.")
                }
                return
            }
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success, success ? nil : "Upload failed") }
        }.resume()
    }
    
    // MARK: - Check if file type is ingestion-compatible
    
    static func isIngestionCompatible(mimeType: String, filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        
        if mimeType.hasPrefix("image/") { return true }
        if mimeType.hasPrefix("video/") { return true }
        if mimeType.hasPrefix("audio/") { return true }
        
        let docExtensions = ["pdf", "doc", "docx", "txt", "rtf", "odt"]
        if docExtensions.contains(ext) { return true }
        if mimeType == "application/pdf" { return true }
        if mimeType.contains("document") { return true }
        
        let spreadsheetExtensions = ["csv", "xlsx", "xls", "ods"]
        if spreadsheetExtensions.contains(ext) { return true }
        if mimeType == "text/csv" { return true }
        if mimeType.contains("spreadsheet") { return true }
        
        return false
    }
    
    // MARK: - Main Upload Handler
    
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
        print("[Upload] File: \(filename), Size: \(data.count) bytes, MIME: \(mimeType)")
        print("[Upload] Endpoint: \(endpoint?.name ?? "none"), KashFiles: \(kashFiles?.name ?? "none")")
        
        // Check size limit
        let sizeCheck = checkSizeLimit(data)
        if !sizeCheck.allowed {
            print("[Upload] ERROR: \(sizeCheck.message ?? "Size limit exceeded")")
            completion(false, sizeCheck.message)
            return
        }
        
        let isImage = mimeType.hasPrefix("image/")
        let isVideo = mimeType.hasPrefix("video/")
        let isAudio = mimeType.hasPrefix("audio/")
        
        switch destination {
            
        // MARK: - Endpoint Only
        case .endpointOnly:
            guard let endpoint = endpoint else {
                completion(false, "No endpoint configured")
                return
            }
            
            if isImage {
                uploadPhoto(data: data, tags: tags, context: context, endpoint: endpoint) { success, error in
                    completion(success, error)
                }
            } else {
                uploadFile(data: data, filename: filename, mimeType: mimeType, tags: tags, endpoint: endpoint, contextPrompt: context.isEmpty ? nil : context) { success, error in
                    completion(success, error)
                }
            }
            
        // MARK: - Kash Files Only
        case .kashFilesOnly:
            guard let kashFiles = kashFiles else {
                completion(false, "No Kash Files configured")
                return
            }
            
            KashFilesClient.uploadFile(data: data, filename: filename, mimeType: mimeType, config: kashFiles) { result in
                switch result {
                case .success(let response):
                    let downloadURL = buildDownloadURL(response: response, config: kashFiles, filename: filename)
                    print("[Upload] Kash Files only - URL: \(downloadURL)")
                    completion(true, downloadURL)
                case .failure(let error):
                    print("[Upload] Kash Files upload failed: \(error)")
                    completion(false, error.localizedDescription)
                }
            }
            
        // MARK: - Link + Caption (Kash Files + link digest, NO AI ingestion)
        case .linkAndCaption:
            guard let kashFiles = kashFiles, let endpoint = endpoint else {
                completion(false, "Both endpoint and Kash Files required for Link + Caption")
                return
            }
            
            KashFilesClient.uploadFile(data: data, filename: filename, mimeType: mimeType, config: kashFiles) { result in
                switch result {
                case .success(let response):
                    let downloadURL = buildDownloadURL(response: response, config: kashFiles, filename: filename)
                    
                    // Create link digest with caption
                    let emoji = getFileEmoji(mimeType: mimeType)
                    var linkNote = "\(emoji) File in Kash Files: \(response.filename ?? filename)\n\n🔗 URL: \(downloadURL)"
                    
                    // Add the caption if provided
                    if !context.isEmpty {
                        linkNote += "\n\n\(context)"
                    }
                    
                    let linkTags = "\(tags),kash-files-link,\(filename)"
                    
                    uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { success in
                        print("[Upload] Link + Caption digest: \(success ? "success" : "failed")")
                        completion(success, downloadURL)
                    }
                    
                case .failure(let error):
                    completion(false, error.localizedDescription)
                }
            }
            
        // MARK: - Both (Kash Files + AI ingestion with URL injected into context)
        case .both:
            guard let endpoint = endpoint, let kashFiles = kashFiles else {
                completion(false, "Both endpoint and Kash Files required")
                return
            }
            
            print("[Upload] Starting BOTH mode upload")
            
            // Step 1: Upload to Kash Files first
            KashFilesClient.uploadFile(data: data, filename: filename, mimeType: mimeType, config: kashFiles) { result in
                switch result {
                case .success(let response):
                    let downloadURL = buildDownloadURL(response: response, config: kashFiles, filename: filename)
                    print("[Upload] Kash Files upload successful - URL: \(downloadURL)")
                    
                    // Step 2: Handle based on content type
                    if isImage {
                        // IMAGES: Single upload to AI with injected link instruction
                        var aiPrompt = context.isEmpty ? "Describe this image" : context
                        var userCaption = ""
                        
                        // Extract caption if present
                        if context.contains("|||CAPTION_SEP|||") {
                            let parts = context.components(separatedBy: "|||CAPTION_SEP|||")
                            if parts.count == 2 {
                                userCaption = parts[0]
                                aiPrompt = parts[1]
                            }
                        }
                        
                        // Build enhanced prompt with URL injection
                        var enhancedPrompt = aiPrompt
                        if !userCaption.isEmpty {
                            enhancedPrompt += "\n\nUser's caption: \(userCaption)"
                        }
                        
                        // FIX: Explicitly append text request
                        enhancedPrompt += "\n\n when you're done, at the very end of your response, YOU MUST append the text ' \(downloadURL)'"
                        
                        // Single upload with injected URL
                        uploadPhoto(data: data, tags: "\(tags),\(filename)", context: enhancedPrompt, endpoint: endpoint) { success, error in
                            print("[Upload] Image with injected link: \(success ? "success" : "failed")")
                            completion(success, success ? downloadURL : error)
                        }
                        
                    } else if isVideo {
                        // VIDEOS: Single upload to AI with injected link instruction (like photos)
                        var aiPrompt = context.isEmpty ? "Describe this video" : context
                        var userCaption = ""
                        
                        // Extract caption if present
                        if context.contains("|||CAPTION_SEP|||") {
                            let parts = context.components(separatedBy: "|||CAPTION_SEP|||")
                            if parts.count == 2 {
                                userCaption = parts[0]
                                aiPrompt = parts[1]
                            }
                        }
                        
                        // Build enhanced prompt with URL injection
                        var enhancedPrompt = aiPrompt
                        if !userCaption.isEmpty {
                            enhancedPrompt += "\n\nUser's caption: \(userCaption)"
                        }
                        
                        // FIX: Explicitly append text request
                        enhancedPrompt += "\n\nwhen you're done, at the very end of your response, YOU MUST append the text ' \(downloadURL)'"
                        
                        // Single upload with injected URL
                        uploadFile(data: data, filename: filename, mimeType: mimeType, tags: "\(tags),\(filename)", endpoint: endpoint, contextPrompt: enhancedPrompt) { success, error in
                            print("[Upload] Video with injected link: \(success ? "success" : "failed")")
                            completion(success, success ? downloadURL : error)
                        }
                        
                    } else if isAudio {
                        // AUDIO: Single upload to AI with injected link instruction
                        var aiPrompt = context.isEmpty ? "Transcribe and describe this audio" : context
                        var userCaption = ""
                        
                        // Extract caption if present
                        if context.contains("|||CAPTION_SEP|||") {
                            let parts = context.components(separatedBy: "|||CAPTION_SEP|||")
                            if parts.count == 2 {
                                userCaption = parts[0]
                                aiPrompt = parts[1]
                            }
                        }
                        
                        // Build enhanced prompt with URL injection
                        var enhancedPrompt = aiPrompt
                        if !userCaption.isEmpty {
                            enhancedPrompt += "\n\nUser's caption: \(userCaption)"
                        }
                        
                        // Keep consistent with photos/videos
                        enhancedPrompt += "\n\nIMPORTANT: At the very end of your response, append the text ' \(downloadURL)'"
                        
                        // Single upload with injected URL
                        uploadFile(data: data, filename: filename, mimeType: mimeType, tags: "\(tags),\(filename)", endpoint: endpoint, contextPrompt: enhancedPrompt) { success, error in
                            print("[Upload] Audio with injected link: \(success ? "success" : "failed")")
                            completion(success, success ? downloadURL : error)
                        }
                        
                    } else if isIngestionCompatible(mimeType: mimeType, filename: filename) {
                        // DOCUMENTS: Upload to ingestion API + create link digest
                        let dispatchGroup = DispatchGroup()
                        var ingestionSuccess = false
                        var linkSuccess = false
                        var ingestionError: String?
                        
                        // Upload to ingestion API for AI processing
                        dispatchGroup.enter()
                        uploadFile(data: data, filename: filename, mimeType: mimeType, tags: tags, endpoint: endpoint, contextPrompt: nil) { success, error in
                            ingestionSuccess = success
                            ingestionError = error
                            print("[Upload] Document ingestion: \(success ? "success" : "failed")")
                            dispatchGroup.leave()
                        }
                        
                        // Create link digest
                        dispatchGroup.enter()
                        let emoji = getFileEmoji(mimeType: mimeType)
                        var linkNote = "\(emoji) Document in Kash Files: \(response.filename ?? filename)\n\n🔗 URL: \(downloadURL)"
                        if !context.isEmpty {
                            linkNote += "\n\n\(context)"
                        }
                        let linkTags = "\(tags),kash-files-link,document,\(filename)"
                        
                        uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { success in
                            linkSuccess = success
                            print("[Upload] Document link digest: \(success ? "success" : "failed")")
                            dispatchGroup.leave()
                        }
                        
                        dispatchGroup.notify(queue: .main) {
                            if ingestionSuccess || linkSuccess {
                                completion(true, downloadURL)
                            } else {
                                completion(false, ingestionError ?? "Both uploads failed")
                            }
                        }
                        
                    } else {
                        // OTHER FILES: Just link digest (not ingestion compatible)
                        let emoji = getFileEmoji(mimeType: mimeType)
                        var linkNote = "\(emoji) File in Kash Files: \(response.filename ?? filename)\n\n🔗 URL: \(downloadURL)"
                        if !context.isEmpty {
                            linkNote += "\n\n\(context)"
                        }
                        let linkTags = "\(tags),kash-files-link,\(filename)"
                        
                        uploadTextNote(text: linkNote, tags: linkTags, endpoint: endpoint) { success in
                            print("[Upload] File link digest: \(success ? "success" : "failed")")
                            completion(success, downloadURL)
                        }
                    }
                    
                case .failure(let error):
                    print("[Upload] Kash Files upload failed in BOTH mode: \(error)")
                    completion(false, "Kash Files upload failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private static func buildDownloadURL(response: KashFilesClient.UploadResponse, config: KashFilesConfig, filename: String) -> String {
        if let download = response.download {
            return "\(config.baseURL)\(download)"
        } else if let location = response.location {
            return "\(config.baseURL)/api/files/\(location)"
        } else {
            return "\(config.baseURL)/files/\(filename)"
        }
    }
    
    private static func getFileEmoji(mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "🖼️" }
        if mimeType.hasPrefix("video/") { return "🎬" }
        if mimeType.hasPrefix("audio/") { return "🎵" }
        if mimeType == "application/pdf" { return "📕" }
        if mimeType == "text/csv" || mimeType.contains("spreadsheet") { return "📊" }
        if mimeType.contains("document") || mimeType == "text/plain" { return "📄" }
        return "📎"
    }
}