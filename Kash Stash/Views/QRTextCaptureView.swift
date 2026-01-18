//
//  QRTextCaptureView.swift
//  Kash Stash
//

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

struct QRTextCaptureView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var scannedText: String = ""
    @State private var showCamera = false
    @State private var showManualEntry = false
    @State private var showShareSheet = false
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                headerSection
                scannedTextDisplay
                actionButtons
                
                Spacer()
                
                instructionText
            }
            .padding(.horizontal, 20)
            .navigationTitle("Scan to Share")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showCamera) {
            BarcodeScannerViewWrapper(
                isPresented: $showCamera,
                onCodeScanned: { code in
                    if scannedText.isEmpty {
                        scannedText = code
                    } else {
                        scannedText += "\n" + code
                    }
                }
            )
        }
        .sheet(isPresented: $showShareSheet) {
            if !scannedText.isEmpty {
                ShareSheetView(text: scannedText)
            }
        }
        #endif
        .alert("Manual Entry", isPresented: $showManualEntry) {
            TextField("Enter code/text", text: $scannedText)
            Button("Cancel", role: .cancel) {}
            Button("OK") {}
        } message: {
            Text("Enter the code or text manually")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Sub-views
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Scan to Share")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Scan barcodes or QR codes, then share to Pulse")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    private var scannedTextDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanned Data")
                    .font(.headline)
                Spacer()
                if !scannedText.isEmpty {
                    Button(action: {
                        scannedText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            ZStack(alignment: .topLeading) {
                TextEditor(text: $scannedText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(scannedText.isEmpty ? Color(.systemGray4) : Color.orange, lineWidth: 2)
                    )
                
                if scannedText.isEmpty {
                    Text("Scan a code or enter manually")
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                #if !targetEnvironment(macCatalyst)
                Button(action: {
                    checkCameraPermissionAndScan()
                }) {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Scan")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                #endif
                
                Button(action: {
                    showManualEntry = true
                }) {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("Manual")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
            
            Button(action: {
                showShareSheet = true
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share to Pulse")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(scannedText.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(scannedText.isEmpty)
        }
    }
    
    private var instructionText: some View {
        VStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.gray)
            Text("Tap Scan again to add more codes")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Camera Permission
    
    #if !targetEnvironment(macCatalyst)
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
                        self.errorMessage = "Camera access is required to scan codes"
                        self.showError = true
                    }
                }
            }
        default:
            errorMessage = "Camera access is required. Please enable it in Settings."
            showError = true
        }
    }
    #endif
}

// MARK: - Share Sheet Wrapper

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
struct ShareSheetView: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Barcode Scanner SwiftUI Wrapper

#if !targetEnvironment(macCatalyst) && canImport(UIKit)
struct BarcodeScannerViewWrapper: View {
    @Binding var isPresented: Bool
    let onCodeScanned: (String) -> Void
    
    var body: some View {
        ZStack {
            BarcodeScannerRepresentable(
                onCodeScanned: { code in
                    onCodeScanned(code)
                    isPresented = false
                }
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(25)
                }
                .padding(.bottom, 60)
            }
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> BarcodeScannerVC {
        let vc = BarcodeScannerVC()
        vc.onCodeScanned = onCodeScanned
        return vc
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerVC, context: Context) {}
}

class BarcodeScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              session.canAddInput(videoInput) else {
            return
        }
        
        session.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        guard session.canAddOutput(metadataOutput) else { return }
        
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [
            .qr, .ean8, .ean13, .upce, .code39, .code39Mod43,
            .code93, .code128, .pdf417, .aztec, .interleaved2of5,
            .itf14, .dataMatrix
        ]
        
        self.captureSession = session
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
        
        addScanOverlay()
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func addScanOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlayView.isUserInteractionEnabled = false
        
        let scanRect = CGRect(
            x: (view.bounds.width - 280) / 2,
            y: (view.bounds.height - 200) / 2,
            width: 280,
            height: 200
        )
        
        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(rect: scanRect).reversing())
        
        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        overlayView.layer.mask = maskLayer
        
        view.addSubview(overlayView)
        
        // Corner brackets
        let cornerLength: CGFloat = 40
        let cornerWidth: CGFloat = 4
        let color = UIColor.systemOrange
        
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (scanRect.minX, scanRect.minY, cornerLength, cornerWidth),
            (scanRect.minX, scanRect.minY, cornerWidth, cornerLength),
            (scanRect.maxX - cornerLength, scanRect.minY, cornerLength, cornerWidth),
            (scanRect.maxX - cornerWidth, scanRect.minY, cornerWidth, cornerLength),
            (scanRect.minX, scanRect.maxY - cornerWidth, cornerLength, cornerWidth),
            (scanRect.minX, scanRect.maxY - cornerLength, cornerWidth, cornerLength),
            (scanRect.maxX - cornerLength, scanRect.maxY - cornerWidth, cornerLength, cornerWidth),
            (scanRect.maxX - cornerWidth, scanRect.maxY - cornerLength, cornerWidth, cornerLength),
        ]
        
        for (x, y, w, h) in corners {
            let cornerView = UIView(frame: CGRect(x: x, y: y, width: w, height: h))
            cornerView.backgroundColor = color
            view.addSubview(cornerView)
        }
        
        // Instruction label
        let label = UILabel()
        label.text = "Align barcode or QR code within frame"
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasScanned = false
        if captureSession?.isRunning == false {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasScanned,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }
        
        hasScanned = true
        
        // Haptic feedback
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Stop session before callback
        captureSession?.stopRunning()
        
        // Callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onCodeScanned?(stringValue)
        }
    }
    
    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
}
#endif
