import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    var extraNote: String = ""
    var photoContextPrompt: String = ""
    var extraTags: String = ""
    var selectedDestination: UploadDestination = .endpointOnly
    
    var config: AppConfig?
    var currentEndpoint: KashStashEndpoint?
    var currentKashFiles: KashFilesConfig?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadConfiguration()
        presentInputIfNeededAndContinue()
    }
    
    func loadConfiguration() {
        let fm = FileManager.default
        let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")?
            .appendingPathComponent("kash_stash_config.json")
        
        print("[ShareExt] Config URL: \(url?.absoluteString ?? "nil")")
        
        guard let cfgURL = url, let data = try? Data(contentsOf: cfgURL) else {
            print("[ShareExt] Failed to load config data")
            return
        }
        
        print("[ShareExt] Loaded \(data.count) bytes of config data")
        
        do {
            let loadedConfig = try JSONDecoder().decode(AppConfig.self, from: data)
            self.config = loadedConfig
            
            print("[ShareExt] ✅ Config loaded successfully")
            print("[ShareExt] Endpoints: \(loadedConfig.endpoints.count)")
            print("[ShareExt] KashFiles: \(loadedConfig.kashFiles.count)")
            print("[ShareExt] Recent tags: \(loadedConfig.recentTags.count)")
            print("[ShareExt] Recent prompts: \(loadedConfig.recentPrompts.count)")
            
            if let lastId = loadedConfig.lastUsedEndpoint {
                currentEndpoint = loadedConfig.endpoints.first(where: { $0.id == lastId })
            } else {
                currentEndpoint = loadedConfig.endpoints.first
            }
            
            currentKashFiles = loadedConfig.kashFiles.first(where: { $0.isActive }) ??
                              loadedConfig.kashFiles.first
            
            print("[ShareExt] Current endpoint: \(currentEndpoint?.name ?? "nil")")
            print("[ShareExt] Current kashFiles: \(currentKashFiles?.name ?? "nil")")
            
            selectedDestination = loadedConfig.defaultUploadDestination
            
        } catch {
            print("[ShareExt] ❌ Failed to decode config: \(error)")
        }
    }
    
    func saveTagsToConfig() {
        guard !extraTags.isEmpty else { return }
        
        let fm = FileManager.default
        let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")?
            .appendingPathComponent("kash_stash_config.json")
        
        guard let cfgURL = url else { return }
        
        var config: AppConfig
        if let data = try? Data(contentsOf: cfgURL),
           let loadedConfig = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loadedConfig
        } else {
            guard let cachedConfig = self.config else { return }
            config = cachedConfig
        }
        
        RecentTagsManager.addTags(extraTags, to: &config)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: cfgURL, options: .atomic)
            self.config = config
            print("[ShareExt] ✅ Tags saved successfully")
        } catch {
            print("[ShareExt] ❌ Failed to save tags: \(error)")
        }
    }
    
    func savePromptsToConfig() {
        let fm = FileManager.default
        guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")?
            .appendingPathComponent("kash_stash_config.json") else { return }
        
        var config: AppConfig
        if let data = try? Data(contentsOf: url),
           let loadedConfig = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loadedConfig
        } else {
            guard let cachedConfig = self.config else { return }
            config = cachedConfig
        }
        
        var configChanged = false
        
        // Save Context Prompts (usually from Photos/Videos)
        if !photoContextPrompt.isEmpty &&
           photoContextPrompt != "Shared from iOS" &&
           photoContextPrompt.count > 10 {
            RecentPromptsManager.addPrompt(photoContextPrompt, to: &config)
            configChanged = true
        }
        
        // Save Notes/Captions (Text uploads or Link+Caption)
        if !extraNote.isEmpty && extraNote.count > 15 {
            RecentPromptsManager.addPrompt(extraNote, to: &config)
            configChanged = true
        }
        
        guard configChanged else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: url, options: .atomic)
            self.config = config
            print("[ShareExt] ✅ Prompts saved successfully")
        } catch {
            print("[ShareExt] ❌ Failed to save prompts: \(error)")
        }
    }
    
    func presentInputIfNeededAndContinue() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            finishWithMessage("Unable to load shared content.")
            return
        }
        
        let hasEndpoint = currentEndpoint != nil
        let hasKashFiles = currentKashFiles != nil
        
        print("[ShareExt] hasEndpoint: \(hasEndpoint), hasKashFiles: \(hasKashFiles)")
        
        if !hasEndpoint && !hasKashFiles {
            finishWithMessage("No endpoint or Kash Files configured. Please set up in the app first.")
            return
        }

        // Detect content types
        let containsImage = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
        }
        
        let containsVideo = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.video.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) ||
            $0.hasItemConformingToTypeIdentifier("public.movie")
        }
        
        let containsAudio = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.mp3.identifier) ||
            $0.hasItemConformingToTypeIdentifier("public.mp3") ||
            $0.hasItemConformingToTypeIdentifier("public.audio")
        }
        
        let containsDocument = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier) ||
            $0.hasItemConformingToTypeIdentifier("public.comma-separated-values-text") ||
            $0.hasItemConformingToTypeIdentifier(UTType.commaSeparatedText.identifier) ||
            $0.hasItemConformingToTypeIdentifier("com.microsoft.word.doc") ||
            $0.hasItemConformingToTypeIdentifier("org.openxmlformats.wordprocessingml.document")
        }
        
        let containsText = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        
        let containsURL = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        
        let containsGenericFile = attachments.contains {
            $0.hasItemConformingToTypeIdentifier("public.file-url") ||
            $0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
        }
        
        print("[ShareExt] Content detection - Image: \(containsImage), Video: \(containsVideo), Audio: \(containsAudio), Document: \(containsDocument), Text: \(containsText), URL: \(containsURL), File: \(containsGenericFile)")
        
        // Determine content category - ORDER MATTERS
        let isMedia = containsImage || containsVideo || containsAudio
        let isDocument = containsDocument && !isMedia
        let isText = (containsText || containsURL) && !isMedia && !containsDocument
        let isFile = containsGenericFile && !isMedia && !containsDocument && !isText
        
        print("[ShareExt] Category - isMedia: \(isMedia), isDocument: \(isDocument), isText: \(isText), isFile: \(isFile)")
        
        if isMedia {
            showDestinationPicker(contentType: .media)
        } else if isDocument {
            showDestinationPicker(contentType: .document)
        } else if isText {
            // Text/URLs go to endpoint only - no Kash Files option for plain text
            if hasEndpoint {
                selectedDestination = .endpointOnly
                showInputForm(contentType: .text)
            } else {
                finishWithMessage("Text sharing requires an endpoint.")
            }
        } else if isFile {
            showDestinationPicker(contentType: .file)
        } else {
            // Default fallback
            if hasEndpoint {
                selectedDestination = .endpointOnly
                showInputForm(contentType: .text)
            } else {
                finishWithMessage("No compatible upload destination.")
            }
        }
    }
    
    enum ContentType {
        case media
        case document
        case file
        case text
    }
    
    func showDestinationPicker(contentType: ContentType) {
        let hasEndpoint = currentEndpoint != nil
        let hasKashFiles = currentKashFiles != nil
        
        print("[ShareExt] showDestinationPicker - contentType: \(contentType), hasEndpoint: \(hasEndpoint), hasKashFiles: \(hasKashFiles)")
        
        var options: [(title: String, subtitle: String, destination: UploadDestination)] = []
        
        switch contentType {
        case .media:
            if hasEndpoint {
                options.append(("📡 AI Ingestion", "Send to AI for processing", .endpointOnly))
            }
            if hasKashFiles {
                options.append(("☁️ Kash Files Only", "Store file only", .kashFilesOnly))
            }
            if hasKashFiles && hasEndpoint {
                options.append(("🔗 Link + Caption", "Store + create link digest", .linkAndCaption))
                options.append(("🔄 Both", "AI + Kash Files link in response", .both))
            }
            
        case .document:
            if hasEndpoint {
                options.append(("📡 AI Ingestion", "AI processes the document", .endpointOnly))
            }
            if hasKashFiles {
                options.append(("☁️ Kash Files Only", "Store file only", .kashFilesOnly))
            }
            if hasKashFiles && hasEndpoint {
                options.append(("🔗 Link + Caption", "Store + create link digest", .linkAndCaption))
                options.append(("🔄 Both", "AI + Store + Link digest", .both))
            }
            
        case .file:
            if hasKashFiles {
                options.append(("☁️ Kash Files Only", "Store file only", .kashFilesOnly))
            }
            if hasKashFiles && hasEndpoint {
                options.append(("🔗 Link + Caption", "Store + create link digest", .linkAndCaption))
            }
            if !hasKashFiles {
                finishWithMessage("This file type requires Kash Files to be configured.")
                return
            }
            
        case .text:
            // Text only goes to endpoint
            if hasEndpoint {
                options.append(("📡 Endpoint", "Send to AI", .endpointOnly))
            }
        }
        
        print("[ShareExt] Built \(options.count) options")
        
        if options.isEmpty {
            finishWithMessage("No upload destinations available.")
            return
        }
        
        if options.count == 1 {
            selectedDestination = options[0].destination
            showInputForm(contentType: contentType)
            return
        }
        
        let alert = UIAlertController(title: "Upload Destination", message: "Choose where to send this content", preferredStyle: .alert)
        
        for option in options {
            let action = UIAlertAction(title: "\(option.title) - \(option.subtitle)", style: .default) { _ in
                self.selectedDestination = option.destination
                self.showInputForm(contentType: contentType)
            }
            alert.addAction(action)
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.finishWithMessage("Upload cancelled.")
        })
        
        present(alert, animated: true)
    }
    
    func showInputForm(contentType: ContentType) {
        // For Kash Files Only - skip the form entirely, just upload
        if selectedDestination == .kashFilesOnly {
            handleIncoming()
            return
        }
        
        let recentTagsArray = config?.recentTags.prefix(10).map { $0.value } ?? []
        let recentPromptsArray = config?.recentPrompts.prefix(5).map { $0.value } ?? []
        
        let isPhoto = (contentType == .media)
        let isFile = (contentType == .document || contentType == .file)
        let isText = (contentType == .text)
        
        let inputVC = ShareInputViewController(
            isPhoto: isPhoto,
            isFile: isFile,
            isText: isText,
            destination: selectedDestination,
            recentTags: recentTagsArray,
            recentPrompts: recentPromptsArray,
            initialTags: extraTags,
            initialPrompt: photoContextPrompt,
            initialNote: extraNote
        )
        
        inputVC.onComplete = { [weak self] tags, prompt, note in
            guard let self = self else { return }
            self.extraTags = tags
            self.photoContextPrompt = prompt
            self.extraNote = note
            self.handleIncoming()
        }
        
        inputVC.onCancel = { [weak self] in
            self?.finishWithMessage("Upload cancelled.")
        }
        
        inputVC.modalPresentationStyle = .formSheet
        present(inputVC, animated: true)
    }

    func handleIncoming() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            finishWithMessage("Unable to load shared content.")
            return
        }

        print("[ShareExt] Processing \(attachments.count) attachments with destination: \(selectedDestination.rawValue)")

        let dispatchGroup = DispatchGroup()
        var uploadTried = false
        var anySuccessful = false
        var kashFilesURL: String?
        var errorMessage: String?
        let resultQueue = DispatchQueue(label: "upload-results")

        for (index, itemProvider) in attachments.enumerated() {
            print("[ShareExt] Attachment \(index) types: \(itemProvider.registeredTypeIdentifiers)")
            
            // MARK: - Audio Handling
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier(UTType.mp3.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier("public.mp3") ||
               itemProvider.hasItemConformingToTypeIdentifier("public.audio") {
                
                print("[ShareExt] Processing as audio")
                dispatchGroup.enter()
                
                let audioTypes = [
                    UTType.mp3.identifier,
                    UTType.audio.identifier,
                    "public.mp3",
                    "public.audio"
                ]
                
                var typeToLoad: String?
                for type in audioTypes {
                    if itemProvider.hasItemConformingToTypeIdentifier(type) {
                        typeToLoad = type
                        break
                    }
                }
                
                guard let loadType = typeToLoad else {
                    dispatchGroup.leave()
                    continue
                }
                
                itemProvider.loadItem(forTypeIdentifier: loadType, options: nil) { [weak self] (audioData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if let error = error {
                        print("[ShareExt] Error loading audio: \(error)")
                        dispatchGroup.leave()
                        return
                    }
                    
                    var data: Data?
                    var filename = "audio_\(Int(Date().timeIntervalSince1970)).mp3"
                    
                    if let url = audioData as? URL {
                        data = try? Data(contentsOf: url)
                        if !url.lastPathComponent.isEmpty {
                            filename = url.lastPathComponent
                        }
                    } else if let directData = audioData as? Data {
                        data = directData
                    }
                    
                    guard let audioBytes = data else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    let sizeCheck = KashStashUploader.checkSizeLimit(audioBytes)
                    if !sizeCheck.allowed {
                        resultQueue.sync { errorMessage = sizeCheck.message }
                        dispatchGroup.leave()
                        return
                    }
                    
                    uploadTried = true
                    let ext = (filename as NSString).pathExtension.lowercased()
                    var mimeType = "audio/mpeg"
                    if ext == "wav" { mimeType = "audio/wav" }
                    else if ext == "m4a" { mimeType = "audio/mp4" }
                    
                    let contextToPass: String
                    if self.selectedDestination == .linkAndCaption {
                        contextToPass = self.extraNote
                    } else if self.selectedDestination == .both && !self.extraNote.isEmpty {
                        contextToPass = "\(self.extraNote)|||CAPTION_SEP|||" + (self.photoContextPrompt.isEmpty ? "Transcribe this audio" : self.photoContextPrompt)
                    } else {
                        contextToPass = self.photoContextPrompt.isEmpty ? "Transcribe this audio" : self.photoContextPrompt
                    }
                    
                    KashStashUploader.uploadWithDestination(
                        data: audioBytes,
                        filename: filename,
                        mimeType: mimeType,
                        tags: self.extraTags,
                        context: contextToPass,
                        destination: self.selectedDestination,
                        endpoint: self.currentEndpoint,
                        kashFiles: self.currentKashFiles
                    ) { success, result in
                        resultQueue.sync {
                            if success {
                                anySuccessful = true
                                if let url = result, url.hasPrefix("http") { kashFilesURL = url }
                            } else if let err = result { errorMessage = err }
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            // MARK: - Video Handling
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier(UTType.video.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier("public.movie") {
                
                print("[ShareExt] Processing as video")
                dispatchGroup.enter()
                
                let videoTypes = [UTType.mpeg4Movie.identifier, UTType.movie.identifier, UTType.video.identifier, "public.movie"]
                
                var typeToLoad: String?
                for type in videoTypes {
                    if itemProvider.hasItemConformingToTypeIdentifier(type) {
                        typeToLoad = type
                        break
                    }
                }
                
                guard let loadType = typeToLoad else {
                    dispatchGroup.leave()
                    continue
                }
                
                itemProvider.loadItem(forTypeIdentifier: loadType, options: nil) { [weak self] (videoData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if let error = error {
                        print("[ShareExt] Error loading video: \(error)")
                        dispatchGroup.leave()
                        return
                    }
                    
                    var data: Data?
                    var filename = "video_\(Int(Date().timeIntervalSince1970)).mp4"
                    
                    if let url = videoData as? URL {
                        data = try? Data(contentsOf: url)
                        if !url.lastPathComponent.isEmpty { filename = url.lastPathComponent }
                    } else if let directData = videoData as? Data {
                        data = directData
                    }
                    
                    guard let videoBytes = data else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    let sizeCheck = KashStashUploader.checkSizeLimit(videoBytes)
                    if !sizeCheck.allowed {
                        resultQueue.sync { errorMessage = sizeCheck.message }
                        dispatchGroup.leave()
                        return
                    }
                    
                    uploadTried = true
                    let ext = (filename as NSString).pathExtension.lowercased()
                    let mimeType = ext == "mov" ? "video/quicktime" : "video/mp4"
                    
                    let contextToPass: String
                    if self.selectedDestination == .linkAndCaption {
                        contextToPass = self.extraNote
                    } else if self.selectedDestination == .both {
                        if !self.extraNote.isEmpty {
                            contextToPass = "\(self.extraNote)|||CAPTION_SEP|||" + (self.photoContextPrompt.isEmpty ? "Describe this video" : self.photoContextPrompt)
                        } else {
                            contextToPass = self.photoContextPrompt.isEmpty ? "Describe this video" : self.photoContextPrompt
                        }
                    } else {
                        contextToPass = self.photoContextPrompt.isEmpty ? "Describe this video" : self.photoContextPrompt
                    }
                    
                    KashStashUploader.uploadWithDestination(
                        data: videoBytes,
                        filename: filename,
                        mimeType: mimeType,
                        tags: self.extraTags,
                        context: contextToPass,
                        destination: self.selectedDestination,
                        endpoint: self.currentEndpoint,
                        kashFiles: self.currentKashFiles
                    ) { success, result in
                        resultQueue.sync {
                            if success {
                                anySuccessful = true
                                if let url = result, url.hasPrefix("http") { kashFilesURL = url }
                            } else if let err = result { errorMessage = err }
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            // MARK: - Image Handling
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                
                print("[ShareExt] Processing as image")
                dispatchGroup.enter()
                
                let typeToLoad = itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ? UTType.png.identifier :
                                itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ? UTType.jpeg.identifier :
                                UTType.image.identifier
                
                itemProvider.loadItem(forTypeIdentifier: typeToLoad, options: nil) { [weak self] (imageData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if let error = error {
                        print("[ShareExt] Error loading image: \(error)")
                        dispatchGroup.leave()
                        return
                    }
                    
                    let image: UIImage?
                    if let url = imageData as? URL {
                        if let data = try? Data(contentsOf: url) {
                            image = UIImage(data: data)
                        } else {
                            image = UIImage(contentsOfFile: url.path)
                        }
                    } else if let data = imageData as? Data {
                        image = UIImage(data: data)
                    } else {
                        image = imageData as? UIImage
                    }
                    
                    guard let img = image, let pngData = img.pngData() else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    let sizeCheck = KashStashUploader.checkSizeLimit(pngData)
                    if !sizeCheck.allowed {
                        resultQueue.sync { errorMessage = sizeCheck.message }
                        dispatchGroup.leave()
                        return
                    }
                    
                    uploadTried = true
                    let filename = "share_\(Int(Date().timeIntervalSince1970)).png"
                    
                    let contextToPass: String
                    if self.selectedDestination == .linkAndCaption {
                        contextToPass = self.extraNote
                    } else if self.selectedDestination == .both {
                        if !self.extraNote.isEmpty {
                            contextToPass = "\(self.extraNote)|||CAPTION_SEP|||" + (self.photoContextPrompt.isEmpty ? "Describe this image" : self.photoContextPrompt)
                        } else {
                            contextToPass = self.photoContextPrompt.isEmpty ? "Describe this image" : self.photoContextPrompt
                        }
                    } else {
                        contextToPass = self.photoContextPrompt.isEmpty ? "Describe this image" : self.photoContextPrompt
                    }
                    
                    KashStashUploader.uploadWithDestination(
                        data: pngData,
                        filename: filename,
                        mimeType: "image/png",
                        tags: self.extraTags,
                        context: contextToPass,
                        destination: self.selectedDestination,
                        endpoint: self.currentEndpoint,
                        kashFiles: self.currentKashFiles
                    ) { success, result in
                        resultQueue.sync {
                            if success {
                                anySuccessful = true
                                if let url = result, url.hasPrefix("http") { kashFilesURL = url }
                            } else if let err = result { errorMessage = err }
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            // MARK: - Document Handling (PDF, CSV, DOC, etc.)
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.commaSeparatedText.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier("public.comma-separated-values-text") ||
                    itemProvider.hasItemConformingToTypeIdentifier("com.microsoft.word.doc") ||
                    itemProvider.hasItemConformingToTypeIdentifier("org.openxmlformats.wordprocessingml.document") ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.spreadsheet.identifier) {
                
                print("[ShareExt] Processing as document")
                dispatchGroup.enter()
                
                let docTypes = [
                    UTType.pdf.identifier,
                    UTType.commaSeparatedText.identifier,
                    "public.comma-separated-values-text",
                    "com.microsoft.word.doc",
                    "org.openxmlformats.wordprocessingml.document",
                    UTType.spreadsheet.identifier,
                    UTType.data.identifier
                ]
                
                var typeToLoad: String?
                for type in docTypes {
                    if itemProvider.hasItemConformingToTypeIdentifier(type) {
                        typeToLoad = type
                        break
                    }
                }
                
                guard let loadType = typeToLoad else {
                    dispatchGroup.leave()
                    continue
                }
                
                itemProvider.loadItem(forTypeIdentifier: loadType, options: nil) { [weak self] (docData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if let error = error {
                        print("[ShareExt] Error loading document: \(error)")
                        dispatchGroup.leave()
                        return
                    }
                    
                    var data: Data?
                    var filename = "document_\(Int(Date().timeIntervalSince1970))"
                    var mimeType = "application/octet-stream"
                    
                    if let url = docData as? URL {
                        data = try? Data(contentsOf: url)
                        filename = url.lastPathComponent
                        let ext = url.pathExtension.lowercased()
                        mimeType = self.mimeTypeForExtension(ext)
                    } else if let directData = docData as? Data {
                        data = directData
                        if loadType == UTType.pdf.identifier {
                            filename += ".pdf"
                            mimeType = "application/pdf"
                        } else if loadType.contains("csv") {
                            filename += ".csv"
                            mimeType = "text/csv"
                        }
                    }
                    
                    guard let docBytes = data else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    let sizeCheck = KashStashUploader.checkSizeLimit(docBytes)
                    if !sizeCheck.allowed {
                        resultQueue.sync { errorMessage = sizeCheck.message }
                        dispatchGroup.leave()
                        return
                    }
                    
                    uploadTried = true
                    
                    KashStashUploader.uploadWithDestination(
                        data: docBytes,
                        filename: filename,
                        mimeType: mimeType,
                        tags: self.extraTags,
                        context: self.extraNote,
                        destination: self.selectedDestination,
                        endpoint: self.currentEndpoint,
                        kashFiles: self.currentKashFiles
                    ) { success, result in
                        resultQueue.sync {
                            if success {
                                anySuccessful = true
                                if let url = result, url.hasPrefix("http") { kashFilesURL = url }
                            } else if let err = result { errorMessage = err }
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            // MARK: - URL Handling
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                print("[ShareExt] Processing as URL")
                dispatchGroup.enter()
                
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (urlData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if let error = error {
                        dispatchGroup.leave()
                        return
                    }
                    
                    var url: URL?
                    if let directUrl = urlData as? URL {
                        url = directUrl
                    } else if let urlStr = urlData as? String {
                        url = URL(string: urlStr)
                    }
                    
                    guard let finalUrl = url else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    if finalUrl.isFileURL {
                        guard let data = try? Data(contentsOf: finalUrl) else {
                            dispatchGroup.leave()
                            return
                        }
                        
                        let filename = finalUrl.lastPathComponent
                        let ext = finalUrl.pathExtension.lowercased()
                        let mimeType = self.mimeTypeForExtension(ext)
                        
                        let sizeCheck = KashStashUploader.checkSizeLimit(data)
                        if !sizeCheck.allowed {
                            resultQueue.sync { errorMessage = sizeCheck.message }
                            dispatchGroup.leave()
                            return
                        }
                        
                        uploadTried = true
                        
                        KashStashUploader.uploadWithDestination(
                            data: data,
                            filename: filename,
                            mimeType: mimeType,
                            tags: self.extraTags,
                            context: self.extraNote,
                            destination: self.selectedDestination,
                            endpoint: self.currentEndpoint,
                            kashFiles: self.currentKashFiles
                        ) { success, result in
                            resultQueue.sync {
                                if success {
                                    anySuccessful = true
                                    if let url = result, url.hasPrefix("http") { kashFilesURL = url }
                                } else if let err = result { errorMessage = err }
                            }
                            dispatchGroup.leave()
                        }
                    } else {
                        guard let endpoint = self.currentEndpoint else {
                            dispatchGroup.leave()
                            return
                        }
                        
                        uploadTried = true
                        var combinedText = finalUrl.absoluteString
                        if !self.extraNote.isEmpty {
                            combinedText += "\n\n\(self.extraNote)"
                        }
                        
                        KashStashUploader.uploadTextNote(text: combinedText, tags: self.extraTags, endpoint: endpoint) { success in
                            resultQueue.sync { anySuccessful = anySuccessful || success }
                            dispatchGroup.leave()
                        }
                    }
                }
            }
            // MARK: - Plain Text Handling
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                print("[ShareExt] Processing as plain text")
                dispatchGroup.enter()
                
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (textData, error) in
                    guard let self = self else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    guard let text = textData as? String, !text.isEmpty else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    guard let endpoint = self.currentEndpoint else {
                        dispatchGroup.leave()
                        return
                    }
                    
                    uploadTried = true
                    var combinedText = text
                    if !self.extraNote.isEmpty {
                        combinedText += "\n\n\(self.extraNote)"
                    }
                    
                    KashStashUploader.uploadTextNote(text: combinedText, tags: self.extraTags, endpoint: endpoint) { success in
                        resultQueue.sync { anySuccessful = anySuccessful || success }
                        dispatchGroup.leave()
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            resultQueue.sync {
                if let error = errorMessage, !anySuccessful {
                    self.finishWithMessage("Upload failed: \(error)")
                } else if !uploadTried {
                    self.finishWithMessage("No shareable content found.")
                } else if anySuccessful {
                    self.saveTagsToConfig()
                    self.savePromptsToConfig()
                    var msg = "Shared to KashStash!"
                    if let url = kashFilesURL { msg += "\n\(url)" }
                    self.finishWithMessage(msg)
                } else {
                    self.finishWithMessage("Upload failed.")
                }
            }
        }
    }
    
    func mimeTypeForExtension(_ ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "csv": return "text/csv"
        case "txt": return "text/plain"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    func finishWithMessage(_ message: String) {
        print("[ShareExt] \(message)")
        let alert = UIAlertController(title: "KashStash", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}

// MARK: - ShareInputViewController

class ShareInputViewController: UIViewController {
    var onComplete: ((String, String, String) -> Void)?
    var onCancel: (() -> Void)?
    
    private let isPhoto: Bool
    private let isFile: Bool
    private let isText: Bool
    private let destination: UploadDestination
    private let recentTags: [String]
    private let recentPrompts: [String]
    
    private var filteredTags: [String] = []
    private var filteredPrompts: [String] = []
    
    private var initialTags: String
    private var initialPrompt: String
    private var initialNote: String
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let tagsField = UITextField()
    private let tagsSearchField = UITextField()
    private let tagsListContainer = UIView()
    private let tagsStackView = UIStackView()
    
    private let promptSearchField = UITextField()
    private let promptsListContainer = UIView()
    private let promptsStackView = UIStackView()
    
    private let promptTextView = UITextView()
    private let noteTextView = UITextView()
    
    private var showPromptField: Bool {
        return isPhoto && (destination == .endpointOnly || destination == .both)
    }
    
    private var showNoteField: Bool {
        if isPhoto {
            return destination == .linkAndCaption
        }
        // Show note field for files AND text
        return isFile || isText
    }
    
    init(isPhoto: Bool, isFile: Bool, isText: Bool, destination: UploadDestination,
         recentTags: [String], recentPrompts: [String],
         initialTags: String, initialPrompt: String, initialNote: String) {
        self.isPhoto = isPhoto
        self.isFile = isFile
        self.isText = isText
        self.destination = destination
        self.recentTags = recentTags
        self.recentPrompts = recentPrompts
        self.filteredTags = recentTags
        self.filteredPrompts = recentPrompts
        self.initialTags = initialTags
        self.initialPrompt = initialPrompt
        self.initialNote = initialNote
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupScrollView()
        setupUI()
        setupKeyboardHandling()
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupUI() {
        let padding: CGFloat = 20
        var lastAnchor = contentView.topAnchor
        var lastOffset: CGFloat = padding
        
        let titleLabel = UILabel()
        titleLabel.text = "Share to Pulse"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        let destLabel = UILabel()
        destLabel.text = "📍 \(destination.displayName)"
        destLabel.font = .systemFont(ofSize: 14)
        destLabel.textColor = .secondaryLabel
        destLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(destLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            destLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            destLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            destLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
        ])
        lastAnchor = destLabel.bottomAnchor
        lastOffset = 20
        
        // Tags
        let tagsLabel = createSectionLabel(text: "Tags")
        contentView.addSubview(tagsLabel)
        NSLayoutConstraint.activate([
            tagsLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            tagsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
        ])
        lastAnchor = tagsLabel.bottomAnchor
        lastOffset = 8
        
        tagsField.text = initialTags
        tagsField.placeholder = "Enter tags (comma separated)"
        tagsField.borderStyle = .roundedRect
        tagsField.autocapitalizationType = .none
        tagsField.autocorrectionType = .no
        tagsField.font = .systemFont(ofSize: 16)
        tagsField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tagsField)
        
        NSLayoutConstraint.activate([
            tagsField.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            tagsField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            tagsField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            tagsField.heightAnchor.constraint(equalToConstant: 44)
        ])
        lastAnchor = tagsField.bottomAnchor
        lastOffset = 12
        
        if !recentTags.isEmpty {
            tagsSearchField.placeholder = "🔍 Search saved tags..."
            tagsSearchField.borderStyle = .roundedRect
            tagsSearchField.autocapitalizationType = .none
            tagsSearchField.font = .systemFont(ofSize: 14)
            tagsSearchField.clearButtonMode = .whileEditing
            tagsSearchField.addTarget(self, action: #selector(tagsSearchChanged), for: .editingChanged)
            tagsSearchField.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(tagsSearchField)
            
            NSLayoutConstraint.activate([
                tagsSearchField.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                tagsSearchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                tagsSearchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
                tagsSearchField.heightAnchor.constraint(equalToConstant: 36)
            ])
            lastAnchor = tagsSearchField.bottomAnchor
            lastOffset = 8
            
            tagsListContainer.translatesAutoresizingMaskIntoConstraints = false
            tagsListContainer.layer.borderColor = UIColor.systemGray4.cgColor
            tagsListContainer.layer.borderWidth = 1
            tagsListContainer.layer.cornerRadius = 8
            tagsListContainer.clipsToBounds = true
            contentView.addSubview(tagsListContainer)
            
            let tagsScrollView = UIScrollView()
            tagsScrollView.translatesAutoresizingMaskIntoConstraints = false
            tagsScrollView.showsVerticalScrollIndicator = true
            tagsListContainer.addSubview(tagsScrollView)
            
            tagsStackView.axis = .vertical
            tagsStackView.spacing = 4
            tagsStackView.translatesAutoresizingMaskIntoConstraints = false
            tagsScrollView.addSubview(tagsStackView)
            
            NSLayoutConstraint.activate([
                tagsListContainer.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                tagsListContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                tagsListContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
                tagsListContainer.heightAnchor.constraint(equalToConstant: 100),
                tagsScrollView.topAnchor.constraint(equalTo: tagsListContainer.topAnchor),
                tagsScrollView.leadingAnchor.constraint(equalTo: tagsListContainer.leadingAnchor),
                tagsScrollView.trailingAnchor.constraint(equalTo: tagsListContainer.trailingAnchor),
                tagsScrollView.bottomAnchor.constraint(equalTo: tagsListContainer.bottomAnchor),
                tagsStackView.topAnchor.constraint(equalTo: tagsScrollView.topAnchor, constant: 8),
                tagsStackView.leadingAnchor.constraint(equalTo: tagsScrollView.leadingAnchor, constant: 8),
                tagsStackView.trailingAnchor.constraint(equalTo: tagsScrollView.trailingAnchor, constant: -8),
                tagsStackView.bottomAnchor.constraint(equalTo: tagsScrollView.bottomAnchor, constant: -8),
                tagsStackView.widthAnchor.constraint(equalTo: tagsScrollView.widthAnchor, constant: -16)
            ])
            rebuildTagsList()
            lastAnchor = tagsListContainer.bottomAnchor
            lastOffset = 20
        }
        
        var promptsAdded = false
        
        if showPromptField {
            let promptLabel = createSectionLabel(text: "AI Context Prompt")
            contentView.addSubview(promptLabel)
            NSLayoutConstraint.activate([
                promptLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                promptLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                promptLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
            ])
            lastAnchor = promptLabel.bottomAnchor
            lastOffset = 8
            
            setupTextView(promptTextView, initialText: initialPrompt, placeholder: "Describe what you want the AI to do...")
            contentView.addSubview(promptTextView)
            
            NSLayoutConstraint.activate([
                promptTextView.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                promptTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                promptTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
                promptTextView.heightAnchor.constraint(equalToConstant: 100)
            ])
            lastAnchor = promptTextView.bottomAnchor
            lastOffset = 12
            
            if !recentPrompts.isEmpty {
                lastAnchor = addPromptsSection(after: lastAnchor, offset: lastOffset, padding: padding, targetTextView: promptTextView)
                lastOffset = 20
                promptsAdded = true
            }
        }
        
        if showNoteField {
            let noteTitle: String
            if isPhoto {
                noteTitle = "Caption/Description"
            } else if isText {
                noteTitle = "Additional Note"
            } else {
                noteTitle = "File Description"
            }
            
            let noteLabel = createSectionLabel(text: noteTitle)
            contentView.addSubview(noteLabel)
            NSLayoutConstraint.activate([
                noteLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
            ])
            lastAnchor = noteLabel.bottomAnchor
            lastOffset = 8
            
            setupTextView(noteTextView, initialText: initialNote, placeholder: "Add a description or note...")
            contentView.addSubview(noteTextView)
            
            NSLayoutConstraint.activate([
                noteTextView.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                noteTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                noteTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
                noteTextView.heightAnchor.constraint(equalToConstant: 80)
            ])
            lastAnchor = noteTextView.bottomAnchor
            lastOffset = 12
            
            // If we haven't added prompts yet, add them here attached to the note field
            if !promptsAdded && !recentPrompts.isEmpty {
                lastAnchor = addPromptsSection(after: lastAnchor, offset: lastOffset, padding: padding, targetTextView: noteTextView)
                lastOffset = 20
                promptsAdded = true
            } else {
                lastOffset = 24
            }
        }
        
        let buttonStack = UIStackView()
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonStack)
        
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("Cancel", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancelBtn.setTitleColor(.systemRed, for: .normal)
        cancelBtn.backgroundColor = .systemRed.withAlphaComponent(0.1)
        cancelBtn.layer.cornerRadius = 12
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        
        let shareBtn = UIButton(type: .system)
        shareBtn.setTitle("Share", for: .normal)
        shareBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        shareBtn.setTitleColor(.white, for: .normal)
        shareBtn.backgroundColor = .systemBlue
        shareBtn.layer.cornerRadius = 12
        shareBtn.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        
        buttonStack.addArrangedSubview(cancelBtn)
        buttonStack.addArrangedSubview(shareBtn)
        
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            buttonStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            buttonStack.heightAnchor.constraint(equalToConstant: 50),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding)
        ])
    }
    
    private func addPromptsSection(after lastAnchor: NSLayoutYAxisAnchor, offset: CGFloat, padding: CGFloat, targetTextView: UITextView) -> NSLayoutYAxisAnchor {
        let promptsSectionLabel = createSectionLabel(text: "Saved Prompts")
        contentView.addSubview(promptsSectionLabel)
        NSLayoutConstraint.activate([
            promptsSectionLabel.topAnchor.constraint(equalTo: lastAnchor, constant: offset),
            promptsSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            promptsSectionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
        ])
        
        promptSearchField.placeholder = "🔍 Search prompts..."
        promptSearchField.borderStyle = .roundedRect
        promptSearchField.font = .systemFont(ofSize: 14)
        promptSearchField.clearButtonMode = .whileEditing
        promptSearchField.addTarget(self, action: #selector(promptsSearchChanged), for: .editingChanged)
        promptSearchField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(promptSearchField)
        
        NSLayoutConstraint.activate([
            promptSearchField.topAnchor.constraint(equalTo: promptsSectionLabel.bottomAnchor, constant: 8),
            promptSearchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            promptSearchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            promptSearchField.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        promptsListContainer.translatesAutoresizingMaskIntoConstraints = false
        promptsListContainer.layer.borderColor = UIColor.systemGray4.cgColor
        promptsListContainer.layer.borderWidth = 1
        promptsListContainer.layer.cornerRadius = 8
        promptsListContainer.clipsToBounds = true
        contentView.addSubview(promptsListContainer)
        
        let promptsScrollView = UIScrollView()
        promptsScrollView.translatesAutoresizingMaskIntoConstraints = false
        promptsListContainer.addSubview(promptsScrollView)
        
        promptsStackView.axis = .vertical
        promptsStackView.spacing = 8
        promptsStackView.translatesAutoresizingMaskIntoConstraints = false
        promptsScrollView.addSubview(promptsStackView)
        
        NSLayoutConstraint.activate([
            promptsListContainer.topAnchor.constraint(equalTo: promptSearchField.bottomAnchor, constant: 8),
            promptsListContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            promptsListContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            promptsListContainer.heightAnchor.constraint(equalToConstant: 120),
            promptsScrollView.topAnchor.constraint(equalTo: promptsListContainer.topAnchor),
            promptsScrollView.leadingAnchor.constraint(equalTo: promptsListContainer.leadingAnchor),
            promptsScrollView.trailingAnchor.constraint(equalTo: promptsListContainer.trailingAnchor),
            promptsScrollView.bottomAnchor.constraint(equalTo: promptsListContainer.bottomAnchor),
            promptsStackView.topAnchor.constraint(equalTo: promptsScrollView.topAnchor, constant: 8),
            promptsStackView.leadingAnchor.constraint(equalTo: promptsScrollView.leadingAnchor, constant: 8),
            promptsStackView.trailingAnchor.constraint(equalTo: promptsScrollView.trailingAnchor, constant: -8),
            promptsStackView.bottomAnchor.constraint(equalTo: promptsScrollView.bottomAnchor, constant: -8),
            promptsStackView.widthAnchor.constraint(equalTo: promptsScrollView.widthAnchor, constant: -16)
        ])
        
        promptsListContainer.tag = targetTextView == promptTextView ? 1 : 2
        rebuildPromptsList()
        return promptsListContainer.bottomAnchor
    }
    
    private func rebuildTagsList() {
        tagsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if filteredTags.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No matching tags"
            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .secondaryLabel
            tagsStackView.addArrangedSubview(emptyLabel)
        } else {
            for (index, tag) in filteredTags.enumerated() {
                let btn = createTagButton(title: "#\(tag)", index: index)
                tagsStackView.addArrangedSubview(btn)
            }
        }
    }
    
    private func rebuildPromptsList() {
        promptsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if filteredPrompts.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No matching prompts"
            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .secondaryLabel
            promptsStackView.addArrangedSubview(emptyLabel)
        } else {
            for (index, prompt) in filteredPrompts.enumerated() {
                let btn = createPromptButton(title: prompt, index: index)
                promptsStackView.addArrangedSubview(btn)
            }
        }
    }
    
    @objc private func tagsSearchChanged() {
        let searchText = tagsSearchField.text?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        filteredTags = searchText.isEmpty ? recentTags : recentTags.filter { $0.lowercased().contains(searchText) }
        rebuildTagsList()
    }
    
    @objc private func promptsSearchChanged() {
        let searchText = promptSearchField.text?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        filteredPrompts = searchText.isEmpty ? recentPrompts : recentPrompts.filter { $0.lowercased().contains(searchText) }
        rebuildPromptsList()
    }
    
    private func createTagButton(title: String, index: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        btn.backgroundColor = .systemBlue.withAlphaComponent(0.1)
        btn.setTitleColor(.systemBlue, for: .normal)
        btn.layer.cornerRadius = 8
        btn.contentHorizontalAlignment = .left
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        btn.tag = index
        btn.addTarget(self, action: #selector(filteredTagButtonTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    private func createPromptButton(title: String, index: Int) -> UIButton {
        let btn = UIButton(type: .system)
        let truncated = title.count > 80 ? String(title.prefix(77)) + "..." : title
        btn.setTitle("💬 \(truncated)", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14)
        btn.titleLabel?.lineBreakMode = .byTruncatingTail
        btn.titleLabel?.numberOfLines = 2
        btn.backgroundColor = .systemGray6
        btn.setTitleColor(.label, for: .normal)
        btn.layer.cornerRadius = 8
        btn.contentHorizontalAlignment = .left
        btn.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        btn.tag = index
        btn.addTarget(self, action: #selector(filteredPromptButtonTapped(_:)), for: .touchUpInside)
        return btn
    }
    
    @objc private func filteredTagButtonTapped(_ sender: UIButton) {
        guard sender.tag < filteredTags.count else { return }
        let tag = filteredTags[sender.tag]
        let currentText = tagsField.text ?? ""
        let currentTags = Set(currentText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        if !currentTags.contains(tag) {
            tagsField.text = currentText.isEmpty ? tag : currentText + "," + tag
        }
    }
    
    @objc private func filteredPromptButtonTapped(_ sender: UIButton) {
        guard sender.tag < filteredPrompts.count else { return }
        let prompt = filteredPrompts[sender.tag]
        let targetTextView: UITextView = (showPromptField && promptsListContainer.tag == 1) ? promptTextView : noteTextView
        if targetTextView.textColor == .placeholderText {
            targetTextView.text = ""
            targetTextView.textColor = .label
        }
        let currentText = targetTextView.text ?? ""
        targetTextView.text = currentText.isEmpty ? prompt : currentText + "\n\n" + prompt
    }
    
    private func createSectionLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func setupTextView(_ textView: UITextView, initialText: String, placeholder: String) {
        textView.text = initialText.isEmpty ? placeholder : initialText
        textView.textColor = initialText.isEmpty ? .placeholderText : .label
        textView.font = .systemFont(ofSize: 16)
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true) { self.onCancel?() }
    }
    
    @objc private func shareTapped() {
        let tags = tagsField.text ?? ""
        var prompt = ""
        if showPromptField {
            prompt = promptTextView.textColor == .placeholderText ? "" : (promptTextView.text ?? "")
        }
        var note = ""
        if showNoteField {
            note = noteTextView.textColor == .placeholderText ? "" : (noteTextView.text ?? "")
        }
        dismiss(animated: true) { self.onComplete?(tags, prompt, note) }
    }
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let insets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.height, right: 0)
        scrollView.contentInset = insets
        scrollView.scrollIndicatorInsets = insets
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }
    
    @objc private func dismissKeyboard() { view.endEditing(true) }
}

extension ShareInputViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = ""
            textView.textColor = .label
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = textView == promptTextView ? "Describe what you want the AI to do..." : "Add a description or note..."
            textView.textColor = .placeholderText
        }
    }
}