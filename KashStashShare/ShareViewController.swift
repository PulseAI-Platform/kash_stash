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

        let dispatchGroup = DispatchGroup()
        var uploadTried = false
        var anySuccessful: Bool = false
        
        // Create a serial queue to safely update our success flag
        let resultQueue = DispatchQueue(label: "upload-results")

        for itemProvider in attachments {
            // IMAGE
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (imageData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[KS-ShareExt] Error loading image: \(error)")
                        return
                    }
                    let image: UIImage?
                    if let url = imageData as? URL {
                        image = UIImage(contentsOfFile: url.path)
                    } else {
                        image = imageData as? UIImage
                    }
                    guard let img = image, let pngData = img.pngData() else {
                        print("[KS-ShareExt] Could not get PNG data from image")
                        return
                    }
                    
                    uploadTried = true
                    let context = self.photoContextPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shared from iOS" : self.photoContextPrompt
                    
                    // Enter the group again for the upload completion
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
                        dispatchGroup.leave() // Leave for the upload completion
                    }
                }
            }
            
            // TEXT
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
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
                    
                    // Enter the group again for the upload completion
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
                        dispatchGroup.leave() // Leave for the upload completion
                    }
                }
            }
            
            // URL
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (urlData, error) in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("[KS-ShareExt] Error loading url: \(error)")
                        return
                    }
                    guard let url = urlData as? URL else {
                        print("[KS-ShareExt] No URL from shared item")
                        return
                    }
                    
                    uploadTried = true
                    let text = url.absoluteString
                    let combinedText = self.combineTextWithExtraNote(text)
                    
                    // Enter the group again for the upload completion
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
                        dispatchGroup.leave() // Leave for the upload completion
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Now we can safely check the result because all completions have finished
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
