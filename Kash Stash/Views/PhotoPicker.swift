import SwiftUI
#if canImport(UIKit)
import PhotosUI
#endif

struct PhotoPicker: View {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        #if os(iOS)
        PhotoPickerIOS(selectedImage: $selectedImage)
        #else
        // Don't use this view on macOS - handle it differently
        EmptyView()
        #endif
    }
}

#if os(iOS)
struct PhotoPickerIOS: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    
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
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPickerIOS
        
        init(_ parent: PhotoPickerIOS) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { (object, error) in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}
#endif
