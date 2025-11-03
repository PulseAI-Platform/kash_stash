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
        
        guard let cfgURL = url, let data = try? Data(contentsOf: cfgURL) else {
            return
        }
        
        guard let loadedConfig = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return
        }
        
        self.config = loadedConfig
        
        if let lastId = loadedConfig.lastUsedEndpoint {
            currentEndpoint = loadedConfig.endpoints.first(where: { $0.id == lastId })
        } else {
            currentEndpoint = loadedConfig.endpoints.first
        }
        
        currentKashFiles = loadedConfig.kashFiles.first(where: { $0.isActive }) ??
                          loadedConfig.kashFiles.first
        
        selectedDestination = loadedConfig.defaultUploadDestination
    }
    
    // 🆕 NEW METHOD: Save tags after successful upload
    func saveTagsToConfig() {
        guard !extraTags.isEmpty else { return }
        
        // Reload config fresh to avoid overwriting main app changes
        let fm = FileManager.default
        let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")?
            .appendingPathComponent("kash_stash_config.json")
        
        guard let cfgURL = url else { return }
        
        // Load the latest config
        var config: AppConfig
        if let data = try? Data(contentsOf: cfgURL),
           let loadedConfig = try? JSONDecoder().decode(AppConfig.self, from: data) {
            config = loadedConfig
        } else {
            // Use our cached one if can't load
            guard var cachedConfig = self.config else { return }
            config = cachedConfig
        }
        
        // Add the new tags
        RecentTagsManager.addTags(extraTags, to: &config)
        
        // Save back
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            
            // Write atomically to prevent corruption
            try data.write(to: cfgURL, options: .atomic)
            
            // Update our local cache
            self.config = config
        } catch {
            // Silent fail - can't log in share extension effectively
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
        
        if !hasEndpoint && !hasKashFiles {
            finishWithMessage("No endpoint or Kash Files configured. Please set up in the app first.")
            return
        }

        // Simple detection like the old working version
        let containsPhoto = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
        }
        let containsText = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        let containsURL = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }
        let containsFile = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
            $0.hasItemConformingToTypeIdentifier("public.file-url")
        }
        
        var isPhoto = containsPhoto
        var isFile = containsFile && !containsPhoto
        var isText = (containsText || containsURL) && !containsPhoto && !containsFile
        
        // Default to text if nothing detected (some apps share differently)
        if !isPhoto && !isFile && !isText {
            isText = true
        }
        
        showDestinationPicker(isPhoto: isPhoto, isFile: isFile, isText: isText)
    }
    
    func showDestinationPicker(isPhoto: Bool, isFile: Bool, isText: Bool) {
        let hasEndpoint = currentEndpoint != nil
        let hasKashFiles = currentKashFiles != nil
        
        var destinationOptions: [(title: String, destination: UploadDestination)] = []
        
        if isFile {
            if hasEndpoint && hasKashFiles {
                selectedDestination = .both
                showTagsPrompt(isPhoto: false, isFile: true, isText: false)
            } else if hasKashFiles {
                selectedDestination = .kashFilesOnly
                showTagsPrompt(isPhoto: false, isFile: true, isText: false)
            } else {
                finishWithMessage("Files require Kash Files to be configured.")
            }
            return
        } else if isText {
            if hasEndpoint {
                selectedDestination = .endpointOnly
                showTagsPrompt(isPhoto: false, isFile: false, isText: true)
            } else {
                finishWithMessage("Text sharing requires an endpoint.")
            }
            return
        } else if isPhoto {
            if hasEndpoint {
                destinationOptions.append(("📡 Endpoint Only", .endpointOnly))
            }
            if hasKashFiles {
                destinationOptions.append(("☁️ Kash Files Only", .kashFilesOnly))
            }
            if hasEndpoint && hasKashFiles {
                destinationOptions.append(("🔄 Both", .both))
            }
        }
        
        if destinationOptions.count == 0 {
            finishWithMessage("No upload destinations available.")
        } else if destinationOptions.count == 1 {
            selectedDestination = destinationOptions[0].destination
            showTagsPrompt(isPhoto: isPhoto, isFile: isFile, isText: isText)
        } else {
            let alert = UIAlertController(title: "Upload Destination", message: nil, preferredStyle: .alert)
            
            for option in destinationOptions {
                alert.addAction(UIAlertAction(title: option.title, style: .default) { _ in
                    self.selectedDestination = option.destination
                    self.showTagsPrompt(isPhoto: isPhoto, isFile: isFile, isText: isText)
                })
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.finishWithMessage("Upload cancelled.")
            })
            
            present(alert, animated: true)
        }
    }
    
    func showTagsPrompt(isPhoto: Bool, isFile: Bool, isText: Bool) {
        // Get recent tags
        let recentTagStrings = config?.recentTags.prefix(10).map { $0.value } ?? []
        
        let alert = UIAlertController(
            title: "Pulse AI Share",
            message: nil,
            preferredStyle: .alert
        )
        
        alert.addTextField { tf in
            tf.placeholder = "Tags (comma separated)"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.text = self.extraTags // Preserve any existing tags
        }
        
        // Add buttons for recent tags (max 5 to keep it clean)
        for tag in recentTagStrings.prefix(5) {
            alert.addAction(UIAlertAction(title: "➕ \(tag)", style: .default) { _ in
                // Get current text
                let currentText = alert.textFields?[0].text ?? ""
                
                // Add tag if not already there
                let currentTags = Set(currentText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                if !currentTags.contains(tag) {
                    if currentText.isEmpty {
                        self.extraTags = tag
                    } else {
                        self.extraTags = currentText + "," + tag
                    }
                } else {
                    self.extraTags = currentText
                }
                
                // Save other fields
                if isPhoto {
                    if self.selectedDestination == .endpointOnly {
                        self.photoContextPrompt = alert.textFields?[1].text ?? ""
                    } else if self.selectedDestination == .kashFilesOnly {
                        self.extraNote = alert.textFields?[1].text ?? ""
                    } else if self.selectedDestination == .both {
                        self.photoContextPrompt = alert.textFields?[1].text ?? ""
                        self.extraNote = alert.textFields?[2].text ?? ""
                    }
                } else if alert.textFields?.count ?? 0 > 1 {
                    self.extraNote = alert.textFields?[1].text ?? ""
                }
                
                // Re-show the prompt with updated tags
                self.showTagsPrompt(isPhoto: isPhoto, isFile: isFile, isText: isText)
            })
        }
        
        if isPhoto {
            if selectedDestination == .endpointOnly {
                alert.addTextField { tf in
                    tf.placeholder = "AI context prompt (optional)"
                    tf.text = self.photoContextPrompt
                }
            } else if selectedDestination == .kashFilesOnly {
                alert.addTextField { tf in
                    tf.placeholder = "Caption/description (optional)"
                    tf.text = self.extraNote
                }
            } else if selectedDestination == .both {
                alert.addTextField { tf in
                    tf.placeholder = "AI context prompt (optional)"
                    tf.text = self.photoContextPrompt
                }
                alert.addTextField { tf in
                    tf.placeholder = "Caption/description (optional)"
                    tf.text = self.extraNote
                }
            }
        } else if isFile {
            alert.addTextField { tf in
                tf.placeholder = "File caption/description (optional)"
                tf.text = self.extraNote
            }
        } else if isText {
            alert.addTextField { tf in
                tf.placeholder = "Additional note (optional)"
                tf.text = self.extraNote
            }
        }
        
        // Cancel button
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.finishWithMessage("Upload cancelled.")
        })
        
        // Share button - using .default style but we'll make it blue
        let shareAction = UIAlertAction(title: "Share", style: .default) { _ in
            self.extraTags = alert.textFields?[0].text ?? ""
            
            if isPhoto {
                if self.selectedDestination == .endpointOnly {
                    self.photoContextPrompt = alert.textFields?[1].text ?? ""
                } else if self.selectedDestination == .kashFilesOnly {
                    self.extraNote = alert.textFields?[1].text ?? ""
                } else if self.selectedDestination == .both {
                    self.photoContextPrompt = alert.textFields?[1].text ?? ""
                    if alert.textFields?.count ?? 0 > 2 {
                        self.extraNote = alert.textFields?[2].text ?? ""
                    }
                }
            } else if alert.textFields?.count ?? 0 > 1 {
                self.extraNote = alert.textFields?[1].text ?? ""
            }
            
            self.handleIncoming()
        }
        alert.addAction(shareAction)
        alert.preferredAction = shareAction // This makes it blue/bold
        
        present(alert, animated: true)
    }

    @objc func dismissPicker() {
        view.endEditing(true)
    }
    @objc func clearTags() {
        if let alert = presentedViewController as? UIAlertController,
           let tf = alert.textFields?.first {
            tf.text = ""
        }
    }

    func handleIncoming() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            print("[ShareExt] No extension item or attachments")
            finishWithMessage("Unable to load shared content.")
            return
        }

        print("[ShareExt] Number of attachments: \(attachments.count)")

        let dispatchGroup = DispatchGroup()
        var uploadTried = false
        var anySuccessful = false
        var kashFilesURL: String?
        let resultQueue = DispatchQueue(label: "upload-results")

        for (index, itemProvider) in attachments.enumerated() {
            print("[ShareExt] Attachment \(index) types: \(itemProvider.registeredTypeIdentifiers)")
            
            // URL - Check for URLs (handles both web URLs and file URLs)
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                print("[ShareExt] Processing as URL")
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (urlData, error) in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("[ShareExt] Error loading url: \(error)")
                        return
                    }
                    
                    // Get URL however it comes
                    var url: URL?
                    if let directUrl = urlData as? URL {
                        url = directUrl
                    } else if let urlStr = urlData as? String {
                        url = URL(string: urlStr)
                    } else if let data = urlData as? Data, let str = String(data: data, encoding: .utf8) {
                        url = URL(string: str)
                    }
                    
                    guard let finalUrl = url else {
                        print("[ShareExt] No URL extracted")
                        return
                    }
                    
                    print("[ShareExt] Got URL: \(finalUrl)")
                    
                    if finalUrl.isFileURL {
                        // IT'S A FILE URL - LOAD THE FILE!
                        print("[ShareExt] URL is a file URL")
                        
                        guard let data = try? Data(contentsOf: finalUrl) else {
                            print("[ShareExt] Failed to load file data from URL")
                            return
                        }
                        
                        let filename = finalUrl.lastPathComponent
                        let ext = finalUrl.pathExtension.lowercased()
                        let imageExtensions = ["jpeg", "jpg", "png", "heic", "heif", "tiff", "bmp", "gif"]
                        
                        uploadTried = true
                        
                        if imageExtensions.contains(ext) {
                            // IMAGE FILE
                            print("[ShareExt] File is an image")
                            let imgFilename = "share_\(Int(Date().timeIntervalSince1970)).png"
                            
                            // Convert to PNG if needed
                            var imageData = data
                            if let image = UIImage(data: data), let pngData = image.pngData() {
                                imageData = pngData
                            }
                            
                            // Handle kashFilesOnly mode specially
                            if self.selectedDestination == .kashFilesOnly && self.currentEndpoint != nil {
                                dispatchGroup.enter()
                                KashFilesClient.uploadFile(
                                    data: imageData,
                                    filename: imgFilename,
                                    mimeType: "image/png",
                                    config: self.currentKashFiles!
                                ) { result in
                                    switch result {
                                    case .success(let response):
                                        var downloadURL: String
                                        if let download = response.download {
                                            downloadURL = "\(self.currentKashFiles!.baseURL)\(download)"
                                        } else if let location = response.location {
                                            downloadURL = "\(self.currentKashFiles!.baseURL)/api/files/\(location)"
                                        } else {
                                            downloadURL = "\(self.currentKashFiles!.baseURL)/files/\(imgFilename)"
                                        }
                                        
                                        var linkNote = ""
                                        if !self.extraNote.isEmpty {
                                            linkNote = self.extraNote + "\n\n"
                                        }
                                        linkNote += "🖼️ Image in Kash Files: \(response.filename ?? imgFilename)\n\nDirect URL: \(downloadURL)"
                                        let linkTags = "\(self.extraTags),kash-files-link,image-link,\(imgFilename)"
                                        
                                        KashStashUploader.uploadTextNote(
                                            text: linkNote,
                                            tags: linkTags,
                                            endpoint: self.currentEndpoint!
                                        ) { linkSuccess in
                                            resultQueue.sync {
                                                anySuccessful = anySuccessful || linkSuccess
                                                kashFilesURL = downloadURL
                                            }
                                            dispatchGroup.leave()
                                        }
                                    case .failure(_):
                                        dispatchGroup.leave()
                                    }
                                }
                            } else {
                                var contextToPass = self.photoContextPrompt.isEmpty ? "Shared from iOS" : self.photoContextPrompt
                                if self.selectedDestination == .both && !self.extraNote.isEmpty {
                                    contextToPass = "\(self.extraNote)|||CAPTION_SEP|||" + contextToPass
                                }
                                
                                dispatchGroup.enter()
                                KashStashUploader.uploadWithDestination(
                                    data: imageData,
                                    filename: imgFilename,
                                    mimeType: "image/png",
                                    tags: self.extraTags,
                                    context: contextToPass,
                                    destination: self.selectedDestination,
                                    endpoint: self.currentEndpoint,
                                    kashFiles: self.currentKashFiles
                                ) { success, url in
                                    print("[ShareExt] Image upload result: \(success)")
                                    resultQueue.sync {
                                        anySuccessful = anySuccessful || success
                                        if let u = url { kashFilesURL = u }
                                    }
                                    dispatchGroup.leave()
                                }
                            }
                        } else {
                            // NON-IMAGE FILE - UPLOAD AS FILE
                            print("[ShareExt] File is not an image: \(filename)")
                            
                            var mimeType = "application/octet-stream"
                            if let uti = UTType(filenameExtension: ext) {
                                mimeType = uti.preferredMIMEType ?? "application/octet-stream"
                            }
                            
                            // Files always use both if available
                            let actualDestination = (self.currentEndpoint != nil && self.currentKashFiles != nil) ?
                                UploadDestination.both : self.selectedDestination
                            
                            dispatchGroup.enter()
                            KashStashUploader.uploadWithDestination(
                                data: data,
                                filename: filename,
                                mimeType: mimeType,
                                tags: self.extraTags,
                                context: self.extraNote,
                                destination: actualDestination,
                                endpoint: self.currentEndpoint,
                                kashFiles: self.currentKashFiles
                            ) { success, url in
                                print("[ShareExt] File upload result: \(success)")
                                resultQueue.sync {
                                    anySuccessful = anySuccessful || success
                                    if let u = url { kashFilesURL = u }
                                }
                                dispatchGroup.leave()
                            }
                        }
                    } else {
                        // WEB URL - treat as text
                        print("[ShareExt] URL is a web URL")
                        uploadTried = true
                        let urlString = finalUrl.absoluteString
                        let combinedText = self.combineTextWithExtraNote(urlString)
                        
                        dispatchGroup.enter()
                        KashStashUploader.uploadTextNote(
                            text: combinedText,
                            tags: self.extraTags,
                            endpoint: self.currentEndpoint!
                        ) { success in
                            print("[ShareExt] URL text upload result: \(success)")
                            resultQueue.sync {
                                anySuccessful = anySuccessful || success
                            }
                            dispatchGroup.leave()
                        }
                    }
                }
            }
            
            // TEXT - Check for plain text
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                print("[ShareExt] Processing as plain text")
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (textData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[ShareExt] Error loading text: \(error)")
                        return
                    }
                    
                    guard let text = textData as? String, !text.isEmpty else {
                        print("[ShareExt] Loaded text is nil/empty")
                        return
                    }
                    
                    uploadTried = true
                    let combinedText = self.combineTextWithExtraNote(text)
                    
                    dispatchGroup.enter()
                    KashStashUploader.uploadTextNote(
                        text: combinedText,
                        tags: self.extraTags,
                        endpoint: self.currentEndpoint!
                    ) { success in
                        print("[ShareExt] Text note upload result: \(success)")
                        resultQueue.sync {
                            anySuccessful = anySuccessful || success
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            
            // IMAGE - Check for actual image types
            else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
                    itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                
                print("[ShareExt] Processing as image")
                dispatchGroup.enter()
                
                let typeToLoad = itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ? UTType.png.identifier :
                                itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ? UTType.jpeg.identifier :
                                UTType.image.identifier
                
                itemProvider.loadItem(forTypeIdentifier: typeToLoad, options: nil) { (imageData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[ShareExt] Error loading image: \(error)")
                        return
                    }
                    
                    let image: UIImage?
                    if let url = imageData as? URL {
                        print("[ShareExt] Image came as URL: \(url)")
                        if let data = try? Data(contentsOf: url) {
                            image = UIImage(data: data)
                        } else {
                            image = UIImage(contentsOfFile: url.path)
                        }
                    } else if let data = imageData as? Data {
                        print("[ShareExt] Image came as Data")
                        image = UIImage(data: data)
                    } else {
                        print("[ShareExt] Image came as UIImage")
                        image = imageData as? UIImage
                    }
                    
                    guard let img = image, let pngData = img.pngData() else {
                        print("[ShareExt] Could not get PNG data from image")
                        return
                    }
                    
                    uploadTried = true
                    let filename = "share_\(Int(Date().timeIntervalSince1970)).png"
                    
                    // Handle kashFilesOnly mode specially
                    if self.selectedDestination == .kashFilesOnly && self.currentEndpoint != nil {
                        dispatchGroup.enter()
                        KashFilesClient.uploadFile(
                            data: pngData,
                            filename: filename,
                            mimeType: "image/png",
                            config: self.currentKashFiles!
                        ) { result in
                            switch result {
                            case .success(let response):
                                var downloadURL: String
                                if let download = response.download {
                                    downloadURL = "\(self.currentKashFiles!.baseURL)\(download)"
                                } else if let location = response.location {
                                    downloadURL = "\(self.currentKashFiles!.baseURL)/api/files/\(location)"
                                } else {
                                    downloadURL = "\(self.currentKashFiles!.baseURL)/files/\(filename)"
                                }
                                
                                var linkNote = ""
                                if !self.extraNote.isEmpty {
                                    linkNote = self.extraNote + "\n\n"
                                }
                                linkNote += "🖼️ Image in Kash Files: \(response.filename ?? filename)\n\nDirect URL: \(downloadURL)"
                                let linkTags = "\(self.extraTags),kash-files-link,image-link,\(filename)"
                                
                                KashStashUploader.uploadTextNote(
                                    text: linkNote,
                                    tags: linkTags,
                                    endpoint: self.currentEndpoint!
                                ) { linkSuccess in
                                    resultQueue.sync {
                                        anySuccessful = anySuccessful || linkSuccess
                                        kashFilesURL = downloadURL
                                    }
                                    dispatchGroup.leave()
                                }
                            case .failure(_):
                                dispatchGroup.leave()
                            }
                        }
                    } else {
                        var contextToPass = self.photoContextPrompt.isEmpty ? "Shared from iOS" : self.photoContextPrompt
                        if self.selectedDestination == .both && !self.extraNote.isEmpty {
                            contextToPass = "\(self.extraNote)|||CAPTION_SEP|||" + contextToPass
                        }
                        
                        dispatchGroup.enter()
                        KashStashUploader.uploadWithDestination(
                            data: pngData,
                            filename: filename,
                            mimeType: "image/png",
                            tags: self.extraTags,
                            context: contextToPass,
                            destination: self.selectedDestination,
                            endpoint: self.currentEndpoint,
                            kashFiles: self.currentKashFiles
                        ) { success, url in
                            print("[ShareExt] Photo upload result: \(success)")
                            resultQueue.sync {
                                anySuccessful = anySuccessful || success
                                if let u = url { kashFilesURL = u }
                            }
                            dispatchGroup.leave()
                        }
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            resultQueue.sync {
                if !uploadTried {
                    print("[ShareExt] No shareable items found after iterating attachments")
                    self.finishWithMessage("No shareable content found.")
                } else if anySuccessful {
                    print("[ShareExt] Success (at least one upload worked)")
                    
                    // 🆕 SAVE TAGS TO RECENT TAGS
                    self.saveTagsToConfig()
                    
                    var msg = "Shared to KashStash!"
                    if let url = kashFilesURL {
                        msg += "\n\(url)"
                    }
                    self.finishWithMessage(msg)
                } else {
                    print("[ShareExt] Upload failed (all attempts failed)")
                    self.finishWithMessage("Upload failed.")
                }
            }
        }
    }
    
    func combineTextWithExtraNote(_ text: String) -> String {
        if !extraNote.isEmpty {
            return text + "\n\n" + extraNote
        }
        return text
    }

    func finishWithMessage(_ message: String) {
        print("[ShareExt] Showing alert: \(message)")
        let alert = UIAlertController(title: "KashStash", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
// Simple picker helper for tag selection
class TagPickerHelper: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
    static let shared = TagPickerHelper()
    var tags: [String] = []
    weak var textField: UITextField?
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return tags.count + 1 // +1 for "Type custom..." option
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if row == 0 {
            return "Type custom tags..."
        }
        return tags[row - 1]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        guard let tf = textField else { return }
        
        if row == 0 {
            // Let them type
            return
        }
        
        let selectedTag = tags[row - 1]
        if let currentText = tf.text, !currentText.isEmpty {
            // Append to existing
            let currentTags = Set(currentText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            if !currentTags.contains(selectedTag) {
                tf.text = currentText + "," + selectedTag
            }
        } else {
            // First tag
            tf.text = selectedTag
        }
    }
}
