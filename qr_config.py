#!/usr/bin/env python3
"""
QR code configuration importer
"""
import json
import base64
from PIL import Image
from pyzbar import pyzbar
import io
from typing import Optional, Dict, Any

class QRConfigImporter:
    @staticmethod
    def decode_qr_from_image(image_path: str) -> Optional[Dict[str, Any]]:
        """
        Extract JSON config from QR code in image
        
        Args:
            image_path: Path to image file containing QR code
            
        Returns:
            Decoded JSON config or None if failed
        """
        try:
            # Open image
            image = Image.open(image_path)
            
            # Decode QR codes
            decoded = pyzbar.decode(image)
            
            if not decoded:
                return None
                
            # Get first QR code data
            qr_data = decoded[0].data.decode('utf-8')
            
            # Parse JSON
            config = json.loads(qr_data)
            
            return config
            
        except Exception as e:
            print(f"QR decode error: {e}")
            return None
    
    @staticmethod
    def detect_config_type(config: Dict[str, Any]) -> str:
        """
        Detect what type of config this is
        
        Returns:
            'kashFiles' - Kash Files instance config
            'mobile_endpoint' - Mobile app endpoint config (basic)
            'pod' - Pod sharing config (entrance_url + preshared_key)
            'unknown' - Unknown type
        """
        # Check for Kash Files config
        if config.get('type') == 'kashFiles':
            return 'kashFiles'
            
        # Check for pod sharing config (has entrance_url and preshared_key)
        if 'entrance_url' in config and 'preshared_key' in config:
            return 'pod'
            
        # Check for mobile endpoint config (has probeKey but NO pod info)
        if 'probeKey' in config:
            return 'mobile_endpoint'
            
        return 'unknown'
    
    @staticmethod
    def convert_mobile_to_desktop(config: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert mobile format config to desktop format
        
        Mobile format uses camelCase and doesn't include pod info
        Desktop format uses UPPER_SNAKE and includes pod fields
        """
        return {
            "name": config.get('name', 'Imported from Mobile'),
            "DEVICE": config.get('device', 'mobile'),
            "PROBE_KEY": config.get('probeKey', ''),
            "NODE_NAME": config.get('nodeName', ''),
            "PROBE_ID": config.get('probeId', '29'),
            # Pod fields start empty - user needs to add pod separately
            "POD_URL": "",
            "POD_KEY": "",
            # Config fields with defaults
            "CONFIG_DIGEST_ID": "",
            "CONFIG_DIGEST_TAGS": "agent-config",
            "CONFIG_CACHE_MINUTES": 5,
            # Desktop-specific
            "KEEP_SCREENSHOTS": False,
            "SCREENSHOT_FOLDER": ""
        }
    
    @staticmethod
    def extract_pod_config(config: Dict[str, Any]) -> Dict[str, str]:
        """
        Extract pod configuration from a pod sharing QR
        
        Returns dict with POD_URL and POD_KEY
        """
        # Pod sharing QR has entrance_url and preshared_key
        pod_url = config.get('entrance_url', '')
        pod_key = config.get('preshared_key', '')
        
        return {
            "POD_URL": pod_url,
            "POD_KEY": pod_key
        }