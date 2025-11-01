#!/usr/bin/env python3
"""
Kash Files client for interacting with Kash Files instances
"""
import requests
import json
import base64
from typing import Optional, List, Dict, Any
from datetime import datetime

class KashFilesClient:
    def __init__(self, instance_config: Dict[str, Any]):
        """
        Initialize Kash Files client with instance configuration
        
        Args:
            instance_config: Dict with keys:
                - name: Display name for this instance
                - url: Base URL of Kash Files instance
                - key: API key (kf_xxx format)
        """
        self.name = instance_config.get("name", "Unnamed")
        self.url = instance_config.get("url", "").rstrip("/")
        self.key = instance_config.get("key", "")
        
    def upload_file(self, 
                   filename: str,
                   file_data: bytes,
                   content_type: str,
                   tags: str = "",
                   description: str = "") -> Dict[str, Any]:
        """Upload a file to Kash Files"""
        try:
            endpoint = f"{self.url}/api/files/upload"
            
            # Prepare multipart form data
            files = {
                'file': (filename, file_data, content_type)
            }
            data = {
                'tags': tags,
                'description': description
            }
            headers = {
                'x-upload-key': f'{self.key}'
            }
            
            response = requests.post(endpoint, files=files, data=data, headers=headers)
            response.raise_for_status()
            
            return response.json()
            
        except Exception as e:
            return {"error": str(e), "success": False}
    
    def search_files(self, tags: str = "", query: str = "") -> List[Dict[str, Any]]:
        """Search files by tags or query"""
        try:
            endpoint = f"{self.url}/api/search"
            params = {}
            if tags:
                params['tags'] = tags
            if query:
                params['q'] = query
                
            headers = {
                'Authorization': f'Bearer {self.key}'
            }
            
            response = requests.get(endpoint, params=params, headers=headers)
            response.raise_for_status()
            
            return response.json().get('files', [])
            
        except Exception as e:
            return []
    
    def get_file(self, file_id: str) -> Optional[bytes]:
        """Download a file by ID"""
        try:
            endpoint = f"{self.url}/api/files/{file_id}"
            headers = {
                'Authorization': f'Bearer {self.key}'
            }
            
            response = requests.get(endpoint, headers=headers)
            response.raise_for_status()
            
            return response.content
            
        except Exception as e:
            return None
    
    def test_connection(self) -> bool:
        """Test if the connection to this Kash Files instance works"""
        try:
            endpoint = f"{self.url}/api/health"
            headers = {
                'Authorization': f'Bearer {self.key}'
            }
            
            response = requests.get(endpoint, headers=headers, timeout=5)
            return response.status_code == 200
            
        except:
            return False