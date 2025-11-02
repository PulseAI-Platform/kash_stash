import Foundation

class KashFilesClient {
    
    // THIS IS THE ACTUAL RESPONSE FORMAT
    struct UploadResponse: Codable {
        let ok: Bool?
        let location: String?
        let key: String?
        let decay: String?
        let download: String?
        let filename: String?
        let error: String?
        let message: String?
    }
    
    static func testConnection(config: KashFilesConfig, completion: @escaping (Bool) -> Void) {
        let urlString = "\(config.baseURL)/api/health"
        
        guard let url = URL(string: urlString) else {
            print("[KashFiles] Invalid test URL: \(urlString)")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.key, forHTTPHeaderField: "x-upload-key")
        request.timeoutInterval = 10
        
        print("[KashFiles] Testing: \(url)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let httpResponse = response as? HTTPURLResponse
            let success = httpResponse?.statusCode == 200
            print("[KashFiles] Test result: \(success), status: \(httpResponse?.statusCode ?? 0)")
            DispatchQueue.main.async {
                completion(success)
            }
        }.resume()
    }
    
    static func uploadFile(
        data: Data,
        filename: String,
        mimeType: String,
        config: KashFilesConfig,
        completion: @escaping (Result<UploadResponse, Error>) -> Void
    ) {
        let uploadURL = "\(config.baseURL)/api/files/upload"
        
        guard let url = URL(string: uploadURL) else {
            completion(.failure(NSError(domain: "KashFiles", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        print("[KashFiles] Uploading \(filename) to: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.key, forHTTPHeaderField: "x-upload-key")
        request.timeoutInterval = 60
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body CORRECTLY
        var body = Data()
        
        // Add the file part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { responseData, response, error in
            if let error = error {
                print("[KashFiles] Network error: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "KashFiles", code: 0, userInfo: [NSLocalizedDescriptionKey: "No response"])))
                }
                return
            }
            
            print("[KashFiles] Status: \(httpResponse.statusCode)")
            
            guard let data = responseData else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "KashFiles", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }
            
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[KashFiles] Response: \(responseStr)")
            }
            
            do {
                let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                
                // Check if it was successful
                if uploadResponse.ok == true {
                    DispatchQueue.main.async {
                        completion(.success(uploadResponse))
                    }
                } else {
                    let errorMsg = uploadResponse.error ?? uploadResponse.message ?? "Upload failed"
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "KashFiles", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                    }
                }
            } catch {
                print("[KashFiles] Parse error: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
}
