import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    var extraNote: String = ""
    var photoContextPrompt: String = ""
    var extraTags: String = ""

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentInputIfNeededAndContinue()
    }

    func presentInputIfNeededAndContinue() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            finishWithMessage("Unable to load shared content.")
            return
        }

        let containsPhoto = attachments.contains { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        let containsText = attachments.contains { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        let containsURL = attachments.contains { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }

        if containsPhoto {
            let alert = UIAlertController(title: "Pulse AI Share", message: "Add context prompt and tags for this photo (optional)", preferredStyle: .alert)
            alert.addTextField { tf in tf.placeholder = "Tags (comma separated)" }
            alert.addTextField { tf in tf.placeholder = "Context prompt (optional)" }
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                self.extraTags = alert.textFields?[0].text ?? ""
                self.photoContextPrompt = alert.textFields?[1].text ?? ""
                self.handleIncoming()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                self.finishWithMessage("Upload cancelled.")
            }))
            present(alert, animated: true)
        } else if containsText || containsURL {
            let alert = UIAlertController(title: "Pulse AI Share", message: "Add tags and extra note for this upload (optional)", preferredStyle: .alert)
            alert.addTextField { tf in tf.placeholder = "Tags (comma separated)" }
            alert.addTextField { tf in tf.placeholder = "Extra note text (optional)" }
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in
                self.extraTags = alert.textFields?[0].text ?? ""
                self.extraNote = alert.textFields?[1].text ?? ""
                self.handleIncoming()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                self.finishWithMessage("Upload cancelled.")
            }))
            present(alert, animated: true)
        } else {
            handleIncoming()
        }
    }

    func handleIncoming() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            print("[KS-ShareExt] No extension item or attachments.")
            finishWithMessage("Unable to load shared content.")
            return
        }
        guard let endpoint = loadCurrentEndpoint() else {
            print("[KS-ShareExt] No endpoint configured. (loadCurrentEndpoint failed)")
            finishWithMessage("No endpoint configured. Please set up in the app first.")
            return
        }
        print("[KS-ShareExt] Using endpoint: \(endpoint)")
        print("[KS-ShareExt] Number of attachments: \(attachments.count)")

        let dispatchGroup = DispatchGroup()
        var uploadTried = false
        var anySuccessful: Bool = false
        
        // Create a serial queue to safely update our success flag
        let resultQueue = DispatchQueue(label: "upload-results")

        for (index, itemProvider) in attachments.enumerated() {
            print("[KS-ShareExt] Attachment \(index) types: \(itemProvider.registeredTypeIdentifiers)")
            
            // IMAGE - Check for actual image types
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
               itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                
                print("[KS-ShareExt] Processing as image")
                dispatchGroup.enter()
                
                let typeToLoad = itemProvider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ? UTType.png.identifier :
                                itemProvider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ? UTType.jpeg.identifier :
                                UTType.image.identifier
                
                itemProvider.loadItem(forTypeIdentifier: typeToLoad, options: nil) { (imageData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[KS-ShareExt] Error loading image: \(error)")
                        return
                    }
                    
                    let image: UIImage?
                    if let url = imageData as? URL {
                        print("[KS-ShareExt] Image came as URL: \(url)")
                        if let data = try? Data(contentsOf: url) {
                            image = UIImage(data: data)
                        } else {
                            image = UIImage(contentsOfFile: url.path)
                        }
                    } else if let data = imageData as? Data {
                        print("[KS-ShareExt] Image came as Data")
                        image = UIImage(data: data)
                    } else {
                        print("[KS-ShareExt] Image came as UIImage")
                        image = imageData as? UIImage
                    }
                    
                    guard let img = image, let pngData = img.pngData() else {
                        print("[KS-ShareExt] Could not get PNG data from image")
                        return
                    }
                    
                    uploadTried = true
                    let context = self.photoContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shared from iOS" : self.photoContextPrompt
                    
                    dispatchGroup.enter()
                    KashStashUploader.uploadPhoto(
                        data: pngData,
                        tags: self.extraTags,
                        context: context,
                        endpoint: endpoint
                    ) { success in
                        print("[KS-ShareExt] Photo upload result: \(success)")
                        resultQueue.sync {
                            anySuccessful = anySuccessful || success
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            
            // TEXT - Check for plain text
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                print("[KS-ShareExt] Processing as plain text")
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (textData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[KS-ShareExt] Error loading text: \(error)")
                        return
                    }
                    
                    guard let text = textData as? String, !text.isEmpty else {
                        print("[KS-ShareExt] Loaded text is nil/empty")
                        return
                    }
                    
                    uploadTried = true
                    let combinedText = self.combineTextWithExtraNote(text)
                    
                    dispatchGroup.enter()
                    KashStashUploader.uploadTextNote(
                        text: combinedText,
                        tags: self.extraTags,
                        endpoint: endpoint
                    ) { success in
                        print("[KS-ShareExt] Text note upload result: \(success)")
                        resultQueue.sync {
                            anySuccessful = anySuccessful || success
                        }
                        dispatchGroup.leave()
                    }
                }
            }
            
            // URL - Check for URLs
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                print("[KS-ShareExt] Processing as URL")
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (urlData, error) in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("[KS-ShareExt] Error loading url: \(error)")
                        return
                    }
                    
                    // Get URL string however it comes
                    var urlString: String?
                    if let url = urlData as? URL {
                        print("[KS-ShareExt] Got URL object: \(url)")
                        
                        // Check if this is an image file URL (from Photos on macOS)
                        let imageExtensions = ["jpeg", "jpg", "png", "heic", "heif", "tiff", "bmp", "gif"]
                        if url.isFileURL && imageExtensions.contains(url.pathExtension.lowercased()) {
                            print("[KS-ShareExt] URL is an image file, loading as image")
                            
                            // Load the image from the file URL
                            if let data = try? Data(contentsOf: url), let image = UIImage(data: data), let pngData = image.pngData() {
                                uploadTried = true
                                let context = self.photoContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shared from macOS" : self.photoContextPrompt
                                
                                dispatchGroup.enter()
                                KashStashUploader.uploadPhoto(
                                    data: pngData,
                                    tags: self.extraTags,
                                    context: context,
                                    endpoint: endpoint
                                ) { success in
                                    print("[KS-ShareExt] Photo from file URL upload result: \(success)")
                                    resultQueue.sync {
                                        anySuccessful = anySuccessful || success
                                    }
                                    dispatchGroup.leave()
                                }
                            } else {
                                print("[KS-ShareExt] Failed to load image from file URL")
                            }
                            return // Don't process as text URL
                        }
                        
                        urlString = url.absoluteString
                    } else if let urlStr = urlData as? String {
                        print("[KS-ShareExt] URL came as string: \(urlStr)")
                        urlString = urlStr
                    } else if let data = urlData as? Data, let str = String(data: data, encoding: .utf8) {
                        print("[KS-ShareExt] URL came as data")
                        urlString = str
                    }
                    
                    guard let text = urlString, !text.isEmpty else {
                        print("[KS-ShareExt] No URL string extracted")
                        return
                    }
                    
                    uploadTried = true
                    let combinedText = self.combineTextWithExtraNote(text)
                    
                    dispatchGroup.enter()
                    KashStashUploader.uploadTextNote(
                        text: combinedText,
                        tags: self.extraTags,
                        endpoint: endpoint
                    ) { success in
                        print("[KS-ShareExt] URL upload result: \(success)")
                        resultQueue.sync {
                            anySuccessful = anySuccessful || success
                        }
                        dispatchGroup.leave()
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            resultQueue.sync {
                if !uploadTried {
                    print("[KS-ShareExt] No shareable items found after iterating attachments")
                    self.finishWithMessage("No shareable text or image found.")
                } else if anySuccessful {
                    print("[KS-ShareExt] Success (at least one upload worked)")
                    self.finishWithMessage("Shared to KashStash!")
                } else {
                    print("[KS-ShareExt] Upload failed (all attempts failed)")
                    self.finishWithMessage("Upload failed.")
                }
            }
        }
    }
    func combineTextWithExtraNote(_ text: String) -> String {
        if !self.extraNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + self.extraNote.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return text
        }
    }

    // MARK: - Endpoints

    func loadCurrentEndpoint() -> KashStashEndpoint? {
        let fm = FileManager.default
        let url = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pulseai.kashstash")?
            .appendingPathComponent("kash_stash_config.json")
        print("[KS-ShareExt] Attempting to load config from: \(url?.path ?? "<nil>")")
        guard let cfgURL = url, let data = try? Data(contentsOf: cfgURL) else {
            print("[KS-ShareExt] No config file found at: \(url?.path ?? "<nil>")")
            return nil
        }
        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            print("[KS-ShareExt] Config file exists but failed to decode")
            return nil
        }
        print("[KS-ShareExt] Loaded config with \(config.endpoints.count) endpoints, lastUsed: \(String(describing: config.lastUsedEndpoint))")
        if let lastId = config.lastUsedEndpoint, let endpoint = config.endpoints.first(where: { $0.id == lastId }) {
            return endpoint
        }
        return config.endpoints.first
    }

    // MARK: - Extension UI flow

    func finishWithMessage(_ message: String) {
        print("[KS-ShareExt] Showing alert: \(message)")
        let alert = UIAlertController(title: "KashStash", message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }
}
