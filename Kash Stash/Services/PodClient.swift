// Services/PodClient.swift
import Foundation

class PodClient {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func advertise(nodeUrl: String, podKey: String) async throws -> AdvertiseResponse {
        // Add /api prefix to the path
        guard let url = URL(string: "\(nodeUrl)/api/pods/advertise") else {
            throw PodError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(podKey, forHTTPHeaderField: "X-POD-KEY")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug logging
        if let httpResponse = response as? HTTPURLResponse {
            print("[PodClient] Advertise response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("[PodClient] Error response: \(responseString)")
                
                // Check if it's HTML (error page)
                if responseString.lowercased().contains("<html") || responseString.lowercased().contains("<!doctype") {
                    throw PodError.invalidResponse("Server returned HTML instead of JSON. The pod endpoint may be incorrect.")
                }
                
                throw PodError.httpError(httpResponse.statusCode, responseString)
            }
        }
        
        do {
            let response = try JSONDecoder().decode(AdvertiseResponse.self, from: data)
            return response
        } catch {
            // Log the actual response for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("[PodClient] Failed to decode advertise response: \(responseString)")
            throw PodError.decodingError("Invalid JSON response from server: \(error.localizedDescription)")
        }
    }
    
    func fetchDigests(
        from node: PodNode,
        tags: [String],
        podKey: String,
        page: Int = 1,
        perPage: Int = 20,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> DigestsResponse {
        // Add /api prefix to the path
        var components = URLComponents(string: "\(node.nodeUrl)/api/pods/digests")
        components?.queryItems = [
            URLQueryItem(name: "tags", value: tags.joined(separator: ",")),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        
        // Add date filters if provided
        let formatter = ISO8601DateFormatter()
        if let startDate = startDate {
            components?.queryItems?.append(
                URLQueryItem(name: "start_date", value: formatter.string(from: startDate))
            )
        }
        if let endDate = endDate {
            components?.queryItems?.append(
                URLQueryItem(name: "end_date", value: formatter.string(from: endDate))
            )
        }
        
        guard let url = components?.url else {
            throw PodError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(podKey, forHTTPHeaderField: "X-POD-KEY")
        
        let (data, response) = try await session.data(for: request)
        
        // Debug logging
        if let httpResponse = response as? HTTPURLResponse {
            print("[PodClient] Digests response status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                let responseString = String(data: data, encoding: .utf8) ?? "No response body"
                print("[PodClient] Error response: \(responseString)")
                
                // Check if it's HTML (error page)
                if responseString.lowercased().contains("<html") || responseString.lowercased().contains("<!doctype") {
                    throw PodError.invalidResponse("Server returned HTML instead of JSON. The pod endpoint may be incorrect.")
                }
                
                throw PodError.httpError(httpResponse.statusCode, responseString)
            }
        }
        
        do {
            let response = try JSONDecoder().decode(DigestsResponse.self, from: data)
            return response
        } catch {
            // Log the actual response for debugging
            let responseString = String(data: data, encoding: .utf8) ?? "No response body"
            print("[PodClient] Failed to decode digests response: \(responseString)")
            throw PodError.decodingError("Invalid JSON response from server: \(error.localizedDescription)")
        }
    }
    
    func discoverNodes(pod: PodConfig) async throws -> [PodNode] {
        // Call advertise on entrance node
        let response = try await advertise(
            nodeUrl: pod.entranceNodeUrl,
            podKey: pod.presharedKey
        )
        
        // Convert response nodes to PodNode objects
        var nodes = [PodNode]()
        
        // Add entrance node
        nodes.append(PodNode(
            nodeUrl: pod.entranceNodeUrl,
            name: response.nodeName,
            advertisedTags: response.advertisedTags,
            status: "active",
            lastSeen: Date()
        ))
        
        // Add discovered nodes
        for nodeInfo in response.nodes {
            nodes.append(PodNode(
                nodeUrl: nodeInfo.url,
                name: nodeInfo.name,
                advertisedTags: [], // Will be populated when we call advertise on them
                status: "discovered",
                lastSeen: Date()
            ))
        }
        
        return nodes
    }
}

enum PodError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(String)
    case invalidResponse(String)
    case httpError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .invalidResponse(let message):
            return message
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        }
    }
}
