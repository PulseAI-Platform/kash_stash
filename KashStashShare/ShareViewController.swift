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
        
        // Debug: print raw JSON
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[ShareExt] Raw config JSON (first 500 chars): \(String(jsonString.prefix(500)))")
        }
        
        do {
            let loadedConfig = try JSONDecoder().decode(AppConfig.self, from: data)
            self.config = loadedConfig
            
            print("[ShareExt] ✅ Config loaded successfully")
            print("[ShareExt] Endpoints: \(loadedConfig.endpoints.count)")
            print("[ShareExt] Recent tags: \(loadedConfig.recentTags.count)")
            print("[ShareExt] Recent tags values: \(loadedConfig.recentTags.map { $0.value })")
            print("[ShareExt] Recent prompts: \(loadedConfig.recentPrompts.count)")
            print("[ShareExt] Recent prompts values: \(loadedConfig.recentPrompts.map { $0.value })")
            
            if let lastId = loadedConfig.lastUsedEndpoint {
                currentEndpoint = loadedConfig.endpoints.first(where: { $0.id == lastId })
            } else {
                currentEndpoint = loadedConfig.endpoints.first
            }
            
            currentKashFiles = loadedConfig.kashFiles.first(where: { $0.isActive }) ??
                              loadedConfig.kashFiles.first
            
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
        
        print("[ShareExt] Saving tags. New count: \(config.recentTags.count)")
        
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
        
        if !photoContextPrompt.isEmpty &&
           photoContextPrompt != "Shared from iOS" &&
           photoContextPrompt.count > 10 {
            RecentPromptsManager.addPrompt(photoContextPrompt, to: &config)
            configChanged = true
        }
        
        if !extraNote.isEmpty && extraNote.count > 15 {
            RecentPromptsManager.addPrompt(extraNote, to: &config)
            configChanged = true
        }
        
        guard configChanged else { return }
        
        print("[ShareExt] Saving prompts. New count: \(config.recentPrompts.count)")
        
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
        
        if !hasEndpoint && !hasKashFiles {
            finishWithMessage("No endpoint or Kash Files configured. Please set up in the app first.")
            return
        }

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
                showInputForm(isPhoto: false, isFile: true, isText: false)
            } else if hasKashFiles {
                selectedDestination = .kashFilesOnly
                showInputForm(isPhoto: false, isFile: true, isText: false)
            } else {
                finishWithMessage("Files require Kash Files to be configured.")
            }
            return
        } else if isText {
            if hasEndpoint {
                selectedDestination = .endpointOnly
                showInputForm(isPhoto: false, isFile: false, isText: true)
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
            showInputForm(isPhoto: isPhoto, isFile: isFile, isText: isText)
        } else {
            let alert = UIAlertController(title: "Upload Destination", message: nil, preferredStyle: .alert)
            
            for option in destinationOptions {
                alert.addAction(UIAlertAction(title: option.title, style: .default) { _ in
                    self.selectedDestination = option.destination
                    self.showInputForm(isPhoto: isPhoto, isFile: isFile, isText: isText)
                })
            }
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                self.finishWithMessage("Upload cancelled.")
            })
            
            present(alert, animated: true)
        }
    }
    
    func showInputForm(isPhoto: Bool, isFile: Bool, isText: Bool) {
        let recentTagsArray = config?.recentTags.prefix(10).map { $0.value } ?? []
        let recentPromptsArray = config?.recentPrompts.prefix(5).map { $0.value } ?? []
        
        print("[ShareExt] showInputForm - recentTags count: \(recentTagsArray.count), values: \(recentTagsArray)")
        print("[ShareExt] showInputForm - recentPrompts count: \(recentPromptsArray.count), values: \(recentPromptsArray)")
        
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
            
            if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                print("[ShareExt] Processing as URL")
                dispatchGroup.enter()
                itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (urlData, error) in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("[ShareExt] Error loading url: \(error)")
                        return
                    }
                    
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
                            print("[ShareExt] File is an image")
                            let imgFilename = "share_\(Int(Date().timeIntervalSince1970)).png"
                            
                            var imageData = data
                            if let image = UIImage(data: data), let pngData = image.pngData() {
                                imageData = pngData
                            }
                            
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
                            print("[ShareExt] File is not an image: \(filename)")
                            
                            var mimeType = "application/octet-stream"
                            if let uti = UTType(filenameExtension: ext) {
                                mimeType = uti.preferredMIMEType ?? "application/octet-stream"
                            }
                            
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
                    
                    self.saveTagsToConfig()
                    self.savePromptsToConfig()
                    
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

// MARK: - ShareInputViewController

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
        return (isPhoto && destination != .endpointOnly) || isFile || isText
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
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Share to Pulse"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
        ])
        lastAnchor = titleLabel.bottomAnchor
        lastOffset = 24
        
        // ===== TAGS SECTION =====
        let tagsLabel = createSectionLabel(text: "Tags")
        contentView.addSubview(tagsLabel)
        NSLayoutConstraint.activate([
            tagsLabel.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
            tagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            tagsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding)
        ])
        lastAnchor = tagsLabel.bottomAnchor
        lastOffset = 8
        
        // Tags input field
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
        
        // Tags search field
        if !recentTags.isEmpty {
            tagsSearchField.placeholder = "🔍 Search saved tags..."
            tagsSearchField.borderStyle = .roundedRect
            tagsSearchField.autocapitalizationType = .none
            tagsSearchField.autocorrectionType = .no
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
            
            // Tags list container with scroll
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
                tagsListContainer.heightAnchor.constraint(equalToConstant: 120),
                
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
        
        // ===== PROMPT FIELD (for photos) =====
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
            
            setupTextView(promptTextView, initialText: initialPrompt, placeholder: "Describe what you want the AI to do with this image...")
            contentView.addSubview(promptTextView)
            
            NSLayoutConstraint.activate([
                promptTextView.topAnchor.constraint(equalTo: lastAnchor, constant: lastOffset),
                promptTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                promptTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
                promptTextView.heightAnchor.constraint(equalToConstant: 100)
            ])
            lastAnchor = promptTextView.bottomAnchor
            lastOffset = 12
            
            // Prompts search and list
            if !recentPrompts.isEmpty {
                lastAnchor = addPromptsSection(after: lastAnchor, offset: lastOffset, padding: padding, targetTextView: promptTextView)
                lastOffset = 20
            }
        }
        
        // ===== NOTE/CAPTION FIELD =====
        if showNoteField {
            let noteTitle: String
            if isPhoto {
                noteTitle = "Caption/Description"
            } else if isFile {
                noteTitle = "File Description"
            } else {
                noteTitle = "Additional Note"
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
                noteTextView.heightAnchor.constraint(equalToConstant: 100)
            ])
            lastAnchor = noteTextView.bottomAnchor
            lastOffset = 12
            
            // Show prompts for text/file shares
            if !isPhoto && !recentPrompts.isEmpty {
                lastAnchor = addPromptsSection(after: lastAnchor, offset: lastOffset, padding: padding, targetTextView: noteTextView)
                lastOffset = 24
            } else {
                lastOffset = 24
            }
        }
        
        // ===== BUTTONS =====
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
        
        promptSearchField.placeholder = "🔍 Search saved prompts..."
        promptSearchField.borderStyle = .roundedRect
        promptSearchField.autocapitalizationType = .none
        promptSearchField.autocorrectionType = .no
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
        promptsScrollView.showsVerticalScrollIndicator = true
        promptsListContainer.addSubview(promptsScrollView)
        
        promptsStackView.axis = .vertical
        promptsStackView.spacing = 8
        promptsStackView.translatesAutoresizingMaskIntoConstraints = false
        promptsScrollView.addSubview(promptsStackView)
        
        NSLayoutConstraint.activate([
            promptsListContainer.topAnchor.constraint(equalTo: promptSearchField.bottomAnchor, constant: 8),
            promptsListContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            promptsListContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            promptsListContainer.heightAnchor.constraint(equalToConstant: 150),
            
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
        
        // Store which text view this prompts section targets
        promptsListContainer.tag = targetTextView == promptTextView ? 1 : 2
        
        rebuildPromptsList()
        
        return promptsListContainer.bottomAnchor
    }
    
    // MARK: - Rebuild Lists
    
    private func rebuildTagsList() {
        tagsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if filteredTags.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "No matching tags"
            emptyLabel.font = .systemFont(ofSize: 14)
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.textAlignment = .center
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
            emptyLabel.textAlignment = .center
            promptsStackView.addArrangedSubview(emptyLabel)
        } else {
            for (index, prompt) in filteredPrompts.enumerated() {
                let btn = createPromptButton(title: prompt, index: index)
                promptsStackView.addArrangedSubview(btn)
            }
        }
    }
    
    // MARK: - Search Handlers
    
    @objc private func tagsSearchChanged() {
        let searchText = tagsSearchField.text?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        
        if searchText.isEmpty {
            filteredTags = recentTags
        } else {
            filteredTags = recentTags.filter { $0.lowercased().contains(searchText) }
        }
        
        rebuildTagsList()
    }
    
    @objc private func promptsSearchChanged() {
        let searchText = promptSearchField.text?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        
        if searchText.isEmpty {
            filteredPrompts = recentPrompts
        } else {
            filteredPrompts = recentPrompts.filter { $0.lowercased().contains(searchText) }
        }
        
        rebuildPromptsList()
    }
    
    // MARK: - Button Creators
    
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
    
    // MARK: - Button Actions
    
    @objc private func filteredTagButtonTapped(_ sender: UIButton) {
        guard sender.tag < filteredTags.count else { return }
        let tag = filteredTags[sender.tag]
        
        let currentText = tagsField.text ?? ""
        let currentTags = Set(currentText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        
        if !currentTags.contains(tag) {
            if currentText.isEmpty {
                tagsField.text = tag
            } else {
                tagsField.text = currentText + "," + tag
            }
        }
    }
    
    @objc private func filteredPromptButtonTapped(_ sender: UIButton) {
        guard sender.tag < filteredPrompts.count else { return }
        let prompt = filteredPrompts[sender.tag]
        
        // Determine which text view to append to
        let targetTextView: UITextView
        if showPromptField && promptsListContainer.tag == 1 {
            targetTextView = promptTextView
        } else {
            targetTextView = noteTextView
        }
        
        if targetTextView.textColor == .placeholderText {
            targetTextView.text = ""
            targetTextView.textColor = .label
        }
        
        let currentText = targetTextView.text ?? ""
        if currentText.isEmpty {
            targetTextView.text = prompt
        } else {
            targetTextView.text = currentText + "\n\n" + prompt
        }
    }
    
    // MARK: - Helper Methods
    
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
    
    // MARK: - Actions
    
    @objc private func cancelTapped() {
        dismiss(animated: true) {
            self.onCancel?()
        }
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
        
        dismiss(animated: true) {
            self.onComplete?(tags, prompt, note)
        }
    }
    
    // MARK: - Keyboard Handling
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        
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
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}

// MARK: - UITextViewDelegate

extension ShareInputViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = ""
            textView.textColor = .label
        }
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            if textView == promptTextView {
                textView.text = "Describe what you want the AI to do with this image..."
            } else {
                textView.text = "Add a description or note..."
            }
            textView.textColor = .placeholderText
        }
    }
}
