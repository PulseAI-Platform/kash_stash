import SwiftUI
import PhotosUI
import Vision
import CoreImage
#if canImport(UIKit)
import UIKit
import AVFoundation
#else
import AppKit
#endif

struct QRImportView: View {
    @ObservedObject var viewModel: KashStashViewModel
    @Environment(\.presentationMode) var presentationMode
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var scannedCode: String?
    @State private var parsedConfig: QRCodeScanner.QRConfigType?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isProcessing = false
    @State private var showImportConfirmation = false
    @State private var importedSuccessfully = false
    
    var body: some View {
        #if os(macOS)
        // macOS specific layout
        VStack(spacing: 30) {
            macOSContent
        }
        .frame(width: 500, height: 600)
        .padding()
        #else
        // iOS layout with NavigationView
        NavigationView {
            VStack(spacing: 30) {
                iOSContent
            }
            .navigationTitle("QR Import")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        #endif
    }
    
    #if os(macOS)
    private func selectFileOnMac() {
        guard !isProcessing else { return }
        
        isProcessing = true
        
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "Select QR Code Image"
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            
            if panel.runModal() == .OK, let url = panel.url {
                self.handleSelectedFile(url: url)
            } else {
                self.isProcessing = false
            }
        }
    }

    private func handleSelectedFile(url: URL) {
        // Load image in background
        DispatchQueue.global(qos: .userInitiated).async {
            if let nsImage = NSImage(contentsOf: url),
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                DispatchQueue.main.async {
                    self.processSelectedImage(cgImage)
                }
            } else {
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = "Failed to load image"
                    self.showError = true
                }
            }
        }
    }
    #endif
    
    #if os(iOS)
    var iOSContent: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Import Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Scan or select a QR code to import endpoint or Kash Files settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)
            
            // Action Buttons
            VStack(spacing: 16) {
                #if !targetEnvironment(macCatalyst)
                Button(action: {
                    checkCameraPermissionAndScan()
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                            .font(.title3)
                        Text("Scan with Camera")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
                #endif
                
                Button(action: {
                    showPhotoPicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                        Text("Select from Photos")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
                
                #if DEBUG
                Button(action: {
                    showManualInput()
                }) {
                    Text("Manual JSON Input (Debug)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                #endif
            }
            .padding(.horizontal, 30)
            
            // Processing indicator
            if isProcessing {
                ProgressView("Processing QR Code...")
                    .padding()
            }
            
            Spacer()
            
            // Recent imports info
            VStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.gray)
                Text("QR codes can be generated from the web portal or shared by other users")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image in
                processSelectedImage(image)
            }
        }
        #if !targetEnvironment(macCatalyst)
        .sheet(isPresented: $showCamera) {
            QRCodeScannerView { code in
                processScannedCode(code)
                showCamera = false
            }
        }
        #endif
        .alert("Import Configuration?", isPresented: $showImportConfirmation) {
            Button("Cancel", role: .cancel) {
                parsedConfig = nil
                scannedCode = nil
            }
            Button("Import") {
                performImport()
            }
        } message: {
            Text(confirmationMessage)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $importedSuccessfully) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Configuration imported successfully!")
        }
    }
    #endif
    
    private var confirmationMessage: String {
        guard let config = parsedConfig else { return "" }
        
        switch config {
        case .endpoint(let ep):
            return "Import endpoint '\(ep.name)' for node '\(ep.nodeName)'?"
        case .kashFiles(let kf):
            return "Import Kash Files instance '\(kf.name)'?"
        case .unknown(_):
            return "Import this configuration?"
        case .invalid:
            return ""
        }
    }
    
    #if os(macOS)
    private func selectFileOnMac() {
        // Prevent multiple file dialogs
        guard !isProcessing else { return }
        
        // FIX: Don't wrap runModal in DispatchQueue.main.async - it's already on main thread
        let panel = NSOpenPanel()
        panel.title = "Select QR Code Image"
        panel.message = "Choose an image file containing a QR code"
        panel.prompt = "Select"
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        // Set processing state BEFORE showing dialog
        isProcessing = true
        
        let response = panel.runModal()
        
        if response == .OK, let url = panel.url {
            // Load and process the image
            DispatchQueue.global(qos: .userInitiated).async {
                var cgImage: CGImage?
                
                // Try loading with CGImageSource (best for files)
                if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                    cgImage = image
                }
                // Fallback to NSImage
                else if let nsImage = NSImage(contentsOf: url) {
                    cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
                }
                
                DispatchQueue.main.async {
                    if let image = cgImage {
                        self.processSelectedImage(image)
                    } else {
                        self.isProcessing = false
                        self.errorMessage = "Failed to load image file"
                        self.showError = true
                    }
                }
            }
        } else {
            // User cancelled
            isProcessing = false
        }
    }
    #endif
    
    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func checkCameraPermissionAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCamera = true
                    } else {
                        self.errorMessage = "Camera access is required to scan QR codes"
                        self.showError = true
                    }
                }
            }
        default:
            errorMessage = "Camera access is required to scan QR codes. Please enable it in Settings."
            showError = true
        }
    }
    #endif
    
    private func processSelectedImage(_ image: CGImage) {
        // FIX: Ensure we're on main thread for state updates
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        QRCodeScanner.detectQRCodeWithEnhancements(from: image) { code in
            // FIX: Ensure all state updates happen on main thread
            DispatchQueue.main.async {
                self.isProcessing = false
                
                if let code = code {
                    self.processScannedCode(code)
                } else {
                    self.errorMessage = "No QR code found in the selected image. Try a clearer image."
                    self.showError = true
                }
            }
        }
    }
    
    private func processScannedCode(_ code: String) {
        scannedCode = code
        parsedConfig = QRCodeScanner.parseQRConfig(code)
        
        switch parsedConfig {
        case .endpoint(_), .kashFiles(_):
            showImportConfirmation = true
        case .unknown(_):
            errorMessage = "QR code contains unrecognized configuration format"
            showError = true
        case .invalid, .none:
            errorMessage = "Invalid QR code or configuration data"
            showError = true
        }
    }
    
    private func performImport() {
        guard let config = parsedConfig else { return }
        
        switch config {
        case .endpoint(let endpoint):
            // Check for duplicates
            if viewModel.config.endpoints.contains(where: {
                $0.probeId == endpoint.probeId && $0.nodeName == endpoint.nodeName
            }) {
                errorMessage = "This endpoint is already configured"
                showError = true
            } else {
                viewModel.addEndpoint(endpoint)
                importedSuccessfully = true
            }
            
        case .kashFiles(let kashFiles):
            // Check for duplicates
            if viewModel.config.kashFiles.contains(where: {
                $0.url == kashFiles.url && $0.key == kashFiles.key
            }) {
                errorMessage = "This Kash Files instance is already configured"
                showError = true
            } else {
                viewModel.addKashFiles(kashFiles)
                importedSuccessfully = true
            }
            
        default:
            break
        }
    }
    
    #if DEBUG
    private func showManualInput() {
        let testEndpoint = """
        {
            "name": "Test Endpoint",
            "device": "Test Device",
            "probeKey": "test-key-123",
            "nodeName": "test-node",
            "probeId": "test-probe-id",
            "keepScreenshots": false
        }
        """
        processScannedCode(testEndpoint)
    }
    #endif
}

// MARK: - Photo Library Picker (iOS only) - Keep as is
#if os(iOS)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    // ... keep existing implementation unchanged
    let completion: (CGImage) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (CGImage) -> Void
        
        init(completion: @escaping (CGImage) -> Void) {
            self.completion = completion
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { (object, error) in
                guard let image = object as? UIImage,
                      let cgImage = image.cgImage else { return }
                
                DispatchQueue.main.async {
                    self.completion(cgImage)
                }
            }
        }
    }
}

// Camera scanner implementation remains unchanged...
#if !targetEnvironment(macCatalyst)
struct QRCodeScannerView: UIViewControllerRepresentable {
    // ... keep existing implementation
    let completion: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(completion: completion)
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    // ... keep all existing implementation
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    let completion: (String) -> Void
    var hasScanned = false
    
    init(completion: @escaping (String) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        addScanningOverlay()
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func addScanningOverlay() {
        // ... keep existing implementation
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.isUserInteractionEnabled = false
        
        let scanRect = CGRect(x: (view.bounds.width - 250) / 2,
                              y: (view.bounds.height - 250) / 2,
                              width: 250,
                              height: 250)
        
        let path = UIBezierPath(rect: view.bounds)
        let scanPath = UIBezierPath(rect: scanRect)
        path.append(scanPath.reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlay.layer.mask = maskLayer
        
        view.addSubview(overlay)
        
        // Add corner brackets
        let cornerLength: CGFloat = 30
        let cornerWidth: CGFloat = 4
        let cornerColor = UIColor.systemBlue
        
        // All corners...
        let topLeft = UIView(frame: CGRect(x: scanRect.minX, y: scanRect.minY, width: cornerLength, height: cornerWidth))
        topLeft.backgroundColor = cornerColor
        view.addSubview(topLeft)
        
        let topLeft2 = UIView(frame: CGRect(x: scanRect.minX, y: scanRect.minY, width: cornerWidth, height: cornerLength))
        topLeft2.backgroundColor = cornerColor
        view.addSubview(topLeft2)
        
        let topRight = UIView(frame: CGRect(x: scanRect.maxX - cornerLength, y: scanRect.minY, width: cornerLength, height: cornerWidth))
        topRight.backgroundColor = cornerColor
        view.addSubview(topRight)
        
        let topRight2 = UIView(frame: CGRect(x: scanRect.maxX - cornerWidth, y: scanRect.minY, width: cornerWidth, height: cornerLength))
        topRight2.backgroundColor = cornerColor
        view.addSubview(topRight2)
        
        let bottomLeft = UIView(frame: CGRect(x: scanRect.minX, y: scanRect.maxY - cornerWidth, width: cornerLength, height: cornerWidth))
        bottomLeft.backgroundColor = cornerColor
        view.addSubview(bottomLeft)
        
        let bottomLeft2 = UIView(frame: CGRect(x: scanRect.minX, y: scanRect.maxY - cornerLength, width: cornerWidth, height: cornerLength))
        bottomLeft2.backgroundColor = cornerColor
        view.addSubview(bottomLeft2)
        
        let bottomRight = UIView(frame: CGRect(x: scanRect.maxX - cornerLength, y: scanRect.maxY - cornerWidth, width: cornerLength, height: cornerWidth))
        bottomRight.backgroundColor = cornerColor
        view.addSubview(bottomRight)
        
        let bottomRight2 = UIView(frame: CGRect(x: scanRect.maxX - cornerWidth, y: scanRect.maxY - cornerLength, width: cornerWidth, height: cornerLength))
        bottomRight2.backgroundColor = cornerColor
        view.addSubview(bottomRight2)
        
        // Add label
        let label = UILabel()
        label.text = "Align QR code within frame"
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 100)
        ])
        
        // Add cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50)
        ])
    }
    
    @objc func cancelTapped() {
        dismiss(animated: true)
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported",
                                   message: "Your device does not support scanning.",
                                   preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                       didOutput metadataObjects: [AVMetadataObject],
                       from connection: AVCaptureConnection) {
        if hasScanned { return }
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
                  let stringValue = readableObject.stringValue else { return }
            
            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            completion(stringValue)
            dismiss(animated: true)
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
#endif
#endif
