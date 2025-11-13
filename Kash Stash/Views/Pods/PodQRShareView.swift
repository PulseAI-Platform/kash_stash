//
//  PodQRShareView.swift
//  Kash Stash
//
//  Created by Matt on 11/11/25.
//

// Views/Pods/PodQRShareView.swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct PodQRShareView: View {
    let pod: PodConfig
    @Environment(\.dismiss) var dismiss
    @State private var qrImage: UIImage?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Pod info header
                VStack(spacing: 8) {
                    Text(pod.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Scan to join this pod")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // QR Code
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 280, height: 280)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(radius: 10)
                        .padding()
                } else {
                    ProgressView()
                        .frame(width: 280, height: 280)
                }
                
                // Instructions
                VStack(spacing: 12) {
                    Label("Anyone with Kash Stash can scan this code to join the pod", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    if !pod.cachedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(pod.cachedTags.prefix(5), id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Share button
                Button(action: shareQRCode) {
                    Label("Share QR Code", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Share Pod")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        // Create the pod data to encode
        let podData: [String: String] = [
            "type": "pod",
            "name": pod.name,
            "entrance_url": pod.entranceNodeUrl,
            "key": pod.presharedKey
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: podData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        // Generate QR code
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(jsonString.utf8)
        filter.correctionLevel = "M"
        
        if let outputImage = filter.outputImage {
            // Scale up the QR code
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                qrImage = UIImage(cgImage: cgImage)
            }
        }
    }
    
    private func shareQRCode() {
        guard let qrImage = qrImage else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                qrImage,
                "Join my pod '\(pod.name)' on Kash Stash!"
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
