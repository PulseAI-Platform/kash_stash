//
//  QRCodeScanner.swift
//  Kash Stash
//

import Foundation
import Vision
import CoreImage
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

class QRCodeScanner {
    
    enum QRConfigType {
        case endpoint(KashStashEndpoint)
        case kashFiles(KashFilesConfig)
        case pod(PodConfig)
        case unknown(String)
        case invalid
    }
    
    // MARK: - Main Detection Method
    
    static func detectQRCodeWithEnhancements(from originalImage: CGImage, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // First, try CIDetector with various options
            if let result = detectWithCoreImage(from: originalImage) {
                DispatchQueue.main.async {
                    completion(result)
                }
                return
            }
            
            // If that fails, completion with nil
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
    
    // MARK: - Core Image Detection (Most Reliable for Static Images)
    
    private static func detectWithCoreImage(from cgImage: CGImage) -> String? {
        // Try multiple CIDetector configurations
        let accuracyLevels = [CIDetectorAccuracyHigh, CIDetectorAccuracyLow]
        
        for accuracy in accuracyLevels {
            // Create fresh context and detector for each attempt
            let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
            
            guard let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: context,
                options: [
                    CIDetectorAccuracy: accuracy,
                    CIDetectorMinFeatureSize: 0.1
                ]
            ) else { continue }
            
            // Try original image
            let ciImage = CIImage(cgImage: cgImage)
            if let result = scanWithDetector(detector, image: ciImage) {
                return result
            }
            
            // Try with orientation fixes (crucial for macOS)
            for orientation in [CGImagePropertyOrientation.up, .down, .left, .right] {
                let oriented = ciImage.oriented(orientation)
                if let result = scanWithDetector(detector, image: oriented) {
                    return result
                }
            }
            
            // Try preprocessed versions
            let preprocessed = [
                enhanceForQR(ciImage),
                convertToHighContrastBW(ciImage),
                sharpenImage(ciImage)
            ]
            
            for processed in preprocessed {
                if let processed = processed,
                   let result = scanWithDetector(detector, image: processed) {
                    return result
                }
            }
        }
        
        return nil
    }
    
    private static func scanWithDetector(_ detector: CIDetector, image: CIImage) -> String? {
        let features = detector.features(in: image)
        
        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature {
                // Clean the message string
                if let message = qrFeature.messageString?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !message.isEmpty {
                    print("QR Code detected: \(message)")
                    return message
                }
            }
        }
        return nil
    }
    
    // MARK: - Image Enhancement Functions
    
    private static func enhanceForQR(_ image: CIImage) -> CIImage? {
        var result = image
        
        // Auto-adjust the image
        let filters = result.autoAdjustmentFilters()
        for filter in filters {
            filter.setValue(result, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                result = output
            }
        }
        
        return result
    }
    
    private static func convertToHighContrastBW(_ image: CIImage) -> CIImage? {
        // Convert to grayscale first
        guard let noirFilter = CIFilter(name: "CIPhotoEffectNoir") else { return nil }
        noirFilter.setValue(image, forKey: kCIInputImageKey)
        guard let grayImage = noirFilter.outputImage else { return nil }
        
        // Apply threshold to make it pure black and white
        guard let thresholdFilter = CIFilter(name: "CIColorMonochrome") else { return nil }
        thresholdFilter.setValue(grayImage, forKey: kCIInputImageKey)
        thresholdFilter.setValue(CIColor.white, forKey: "inputColor")
        thresholdFilter.setValue(1.0, forKey: "inputIntensity")
        
        guard let monoImage = thresholdFilter.outputImage else { return nil }
        
        // Boost contrast
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return nil }
        contrastFilter.setValue(monoImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(2.0, forKey: kCIInputContrastKey)
        contrastFilter.setValue(0.5, forKey: kCIInputBrightnessKey)
        
        return contrastFilter.outputImage
    }
    
    private static func sharpenImage(_ image: CIImage) -> CIImage? {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(1.0, forKey: "inputSharpness")
        filter.setValue(1.0, forKey: "inputRadius")
        return filter.outputImage
    }
    
    // MARK: - macOS Specific Image Loading Fix
    
    #if os(macOS)
    static func loadImageForQRDetection(from url: URL) -> CGImage? {
        // This is crucial for macOS - load the image properly
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        return image
    }
    #endif
    
    // MARK: - Config Parsing (updated with better Pod support)
    
    static func parseQRConfig(_ jsonString: String) -> QRConfigType {
        let cleanedString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedString.data(using: .utf8) else {
            return .invalid
        }
        
        // Try to parse as JSON dictionary first
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check if it's explicitly a pod (with type field)
                if let type = json["type"] as? String, type == "pod" {
                    if let pod = parsePodConfig(json) {
                        return .pod(pod)
                    }
                }
                
                // Check if it looks like a pod (has preshared_key or entrance_url)
                if json["preshared_key"] != nil || json["entrance_url"] != nil {
                    if let pod = parsePodConfig(json) {
                        return .pod(pod)
                    }
                }
                
                // Check for endpoint markers
                if json["probeKey"] != nil || json["probe_key"] != nil {
                    if let endpoint = parseAndroidEndpoint(json) {
                        return .endpoint(endpoint)
                    }
                }
                
                // Check for KashFiles markers (has url and key but NOT entrance_url)
                if json["url"] != nil && json["key"] != nil && json["entrance_url"] == nil {
                    if let kashFiles = parseAndroidKashFiles(json) {
                        return .kashFiles(kashFiles)
                    }
                }
            }
        } catch {
            print("Failed to parse as JSON: \(error)")
        }
        
        // Try to parse as direct endpoint object
        do {
            let endpoint = try JSONDecoder().decode(KashStashEndpoint.self, from: data)
            return .endpoint(endpoint)
        } catch {
            print("Failed to decode as endpoint: \(error)")
        }
        
        // Try to parse as Kash Files config
        do {
            let kashFiles = try JSONDecoder().decode(KashFilesConfig.self, from: data)
            return .kashFiles(kashFiles)
        } catch {
            print("Failed to decode as KashFiles: \(error)")
        }
        
        return .unknown(cleanedString)
    }
    
    private static func parsePodConfig(_ dict: [String: Any]) -> PodConfig? {
        // Handle both formats - the one we expected and the actual format
        guard let name = dict["name"] as? String,
              let entranceUrl = dict["entrance_url"] as? String else {
            return nil
        }
        
        // Try both "key" and "preshared_key" fields
        guard let key = (dict["key"] as? String) ?? (dict["preshared_key"] as? String) else {
            return nil
        }
        
        // Get tags if available
        let tags = dict["tags"] as? [String] ?? []
        
        var config = PodConfig(
            name: name,
            entranceNodeUrl: entranceUrl,
            presharedKey: key
        )
        
        // If tags were provided, set them as cached tags
        if !tags.isEmpty {
            config.cachedTags = tags
        }
        
        return config
    }
    
    private static func parseAndroidEndpoint(_ dict: [String: Any]) -> KashStashEndpoint? {
        let name = dict["name"] as? String ?? "Imported Endpoint"
        let device = dict["device"] as? String ?? dict["device_name"] as? String ?? ""
        let probeKey = dict["probeKey"] as? String ?? dict["probe_key"] as? String ?? ""
        let nodeName = dict["nodeName"] as? String ?? dict["node_name"] as? String ?? ""
        let probeId = dict["probeId"] as? String ?? dict["probe_id"] as? String ?? ""
        let keepScreenshots = dict["keepScreenshots"] as? Bool ?? dict["keep_screenshots"] as? Bool ?? false
        
        guard !probeKey.isEmpty, !nodeName.isEmpty, !probeId.isEmpty else {
            return nil
        }
        
        return KashStashEndpoint(
            id: UUID(),
            name: name,
            device: device,
            probeKey: probeKey,
            nodeName: nodeName,
            probeId: probeId,
            keepScreenshots: keepScreenshots
        )
    }
    
    private static func parseAndroidKashFiles(_ dict: [String: Any]) -> KashFilesConfig? {
        let name = dict["name"] as? String ?? "Imported Kash Files"
        guard let url = dict["url"] as? String,
              let key = dict["key"] as? String else {
            return nil
        }
        
        return KashFilesConfig(
            name: name,
            url: url,
            key: key,
            isActive: false
        )
    }
}
