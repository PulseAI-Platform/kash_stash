#!/usr/bin/env python3
import os
import sys
import json
import base64
import subprocess
import tempfile
import time
import requests
import argparse
import webbrowser
from datetime import datetime
from PIL import Image
import pystray
import tkinter as tk
from tkinter import simpledialog, messagebox, filedialog
from queue_boss import QueueBoss
import threading
from kash_files import KashFilesClient
from qr_config import QRConfigImporter

CONFIG_PATH = os.path.expanduser("~/.kash_stash_config.json")

DEFAULT_PROBE_ID = "29"

def resource_path(filename):
    """Get the absolute path to a bundled resource"""
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, filename)
    return os.path.abspath(filename)

class SimpleTagDialog:
    """Simplified tag dialog that doesn't cause Windows lockups"""
    def __init__(self, recent_tags):
        self.result = None
        self.recent_tags = recent_tags
        
    def show(self):
        """Show a simplified tag selection dialog"""
        root = tk.Tk()
        root.withdraw()
        
        # Build options text
        options_text = "Recent tag combinations:\n\n"
        for i, entry in enumerate(self.recent_tags[:10]):  # Show last 10
            tags = entry['value']
            if len(tags) > 60:
                tags = tags[:57] + "..."
            options_text += f"{i+1}: {tags}\n"
        
        options_text += "\nEnter number (1-10) to use recent tags,\nor enter new tags (comma-separated):"
        
        result = simpledialog.askstring("Select Tags", options_text)
        
        if result:
            # Check if it's a number selection
            try:
                idx = int(result) - 1
                if 0 <= idx < len(self.recent_tags) and idx < 10:
                    self.result = self.recent_tags[idx]['value']
                else:
                    self.result = result
            except ValueError:
                # Not a number, treat as new tags
                self.result = result
        
        root.destroy()
        return self.result

class KashStash:
    def __init__(self, headless=False):
        self.headless = headless
        self.cfg = self.load_config()
        # Migrate old configs if needed
        self.migrate_config()
        # Initialize Kash Files clients
        self.kash_files_clients = []
        self.update_kash_files_clients()
        
        if not self.cfg.get("endpoints"):
            if self.headless:
                print("ERROR: No endpoints configured. Run without --headless first to set up configuration.", file=sys.stderr)
                sys.exit(1)
            else:
                self.setup_initial_config()
    
    def load_config(self):
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH) as f:
                return json.load(f)
        return {
            "endpoints": [], 
            "kashFiles": [], 
            "recent_tags": [],
            "last_used_endpoint": 0, 
            "last_used_kash_files": 0
        }
    
    def save_config(self):
        with open(CONFIG_PATH, "w") as f:
            json.dump(self.cfg, f, indent=2)
    
    def migrate_config(self):
        """Remove deprecated queue tag fields from existing configs and ensure required fields exist"""
        migrated = False
        deprecated_fields = ['QUEUE_TAGS', 'LOCK_TAGS', 'DONE_TAGS', 'LOGIC_TAGS']
        
        for endpoint in self.cfg.get("endpoints", []):
            for field in deprecated_fields:
                if field in endpoint:
                    del endpoint[field]
                    migrated = True
        
        # Ensure kashFiles array exists
        if 'kashFiles' not in self.cfg:
            self.cfg['kashFiles'] = []
            migrated = True
        
        # Ensure recent_tags array exists
        if 'recent_tags' not in self.cfg:
            self.cfg['recent_tags'] = []
            migrated = True
        
        if migrated:
            print("[KashStash] Migrated config to new format")
            self.save_config()
    
    def update_recent_tags(self, tags):
        """Update recent tags history"""
        if not tags:
            return
        
        # Get current timestamp
        timestamp = datetime.now().isoformat()
        
        # Check if this tag combination already exists
        recent_tags = self.cfg.get('recent_tags', [])
        
        # Look for existing entry
        found = False
        for entry in recent_tags:
            if entry['value'] == tags:
                entry['lastused'] = timestamp
                found = True
                break
        
        if not found:
            # Add new entry
            recent_tags.insert(0, {
                'value': tags,
                'lastused': timestamp
            })
        
        # Sort by lastused (most recent first)
        recent_tags.sort(key=lambda x: x.get('lastused', ''), reverse=True)
        
        # Limit to 50 entries
        self.cfg['recent_tags'] = recent_tags[:50]
        self.save_config()
    
    def select_tags_dialog(self):
        """Show simplified tag selector dialog"""
        dialog = SimpleTagDialog(self.cfg.get('recent_tags', []))
        result = dialog.show()
        return result if result else ""
    
    def update_kash_files_clients(self):
        """Update the list of Kash Files client instances"""
        self.kash_files_clients = []
        for kf_config in self.cfg.get("kashFiles", []):
            client = KashFilesClient(kf_config)
            client.upload_endpoint = "/api/files/upload"
            self.kash_files_clients.append(client)
    
    def open_node_portal(self):
        """Open the node portal in browser"""
        endpoint = self.get_current_endpoint()
        if not endpoint:
            if not self.headless:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "No endpoint configured!")
                root.destroy()
            return
        
        node_name = endpoint.get('NODE_NAME', '')
        if not node_name:
            if not self.headless:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "Endpoint has no NODE_NAME configured!")
                root.destroy()
            return
        
        url = f"https://pulse-{node_name}.xyzpulseinfra.com"
        webbrowser.open(url)
        
        if not self.headless:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Browser", f"Opening: {url}")
            root.destroy()
    
    def open_blog(self):
        """Open the Pulse AI blog"""
        url = "https://blog.pulseaiplatform.com"
        webbrowser.open(url)
    
    def open_portal(self):
        """Open the Pulse AI portal"""
        url = "https://pulseaiplatform.com"
        webbrowser.open(url)
    
    def upload_file_with_note(self):
        """Upload a file to Kash Files and create a note with the link"""
        # Check if we have Kash Files configured
        kash_files = self.get_current_kash_files()
        if not kash_files:
            if not self.headless:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "No Kash Files instance configured!\nPlease configure one in Manage Config.")
                root.destroy()
            return
        
        # Select file
        root = tk.Tk()
        root.withdraw()
        
        file_path = filedialog.askopenfilename(
            title="Select File to Upload",
            filetypes=[("All files", "*.*")]
        )
        
        if not file_path:
            root.destroy()
            return
        
        root.destroy()
        
        # Read file
        try:
            with open(file_path, 'rb') as f:
                file_data = f.read()
            
            filename = os.path.basename(file_path)
            
            # Detect content type
            import mimetypes
            content_type, _ = mimetypes.guess_type(file_path)
            if not content_type:
                content_type = 'application/octet-stream'
            
        except Exception as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Failed to read file: {e}")
            root.destroy()
            return
        
        # Upload to Kash Files first
        try:
            # Make the request directly since we need the raw response
            endpoint = f"{kash_files['url']}/api/files/upload"
            
            files = {
                'file': (filename, file_data, content_type)
            }
            headers = {
                'x-upload-key': f'{kash_files["key"]}'
            }
            
            response = requests.post(endpoint, files=files, headers=headers)
            response.raise_for_status()
            
            result = response.json()
            
            # Check if upload was successful
            if not result.get('ok'):
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "File upload failed")
                root.destroy()
                return
            
            # Extract the download URL
            download_path = result.get('download', '')
            if not download_path:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "No download URL in response")
                root.destroy()
                return
            
            # Construct full URL
            file_url = f"{kash_files['url']}{download_path}"
            
            # Show success
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Upload Success", f"File uploaded successfully!\n\nURL: {file_url}")
            root.destroy()
            
        except Exception as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Upload failed: {e}")
            root.destroy()
            return
        
        # Now create a note with the link
        note_text = f"File: {filename}\nLink: {file_url}\n\n"
        
        # Get additional context
        context = self.large_text_dialog("Add File Description", note_text)
        if not context:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Info", "Note cancelled - file was still uploaded")
            root.destroy()
            return
        
        # Get tags
        user_tags = self.select_tags_dialog()
        
        # Update recent tags
        if user_tags:
            self.update_recent_tags(user_tags)
        
        # Build full note
        note_filename = f"file_note_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        endpoint = self.get_current_endpoint()
        
        if endpoint:
            full_tags = self.build_tags(user_tags, endpoint, note_filename)
            note_data = context.encode('utf-8')
            
            # Upload the note to the endpoint
            self.upload_file(note_filename, note_data, "text/plain", full_tags, context, endpoint)
        else:
            root = tk.Tk()
            root.withdraw()
            messagebox.showwarning("Warning", "No endpoint configured for note upload")
            root.destroy()
    
    def setup_initial_config(self):
        root = tk.Tk()
        root.withdraw()
        
        # Ask if they want to import from QR or configure manually
        choice = messagebox.askyesnocancel(
            "Kash Stash Setup",
            "Welcome to Kash Stash!\n\n"
            "Do you have a QR code to import?\n\n"
            "Yes = Import from QR code\n"
            "No = Manual configuration\n"
            "Cancel = Exit"
        )
        
        if choice is None:  # Cancel
            root.destroy()
            sys.exit(0)
        elif choice:  # Yes - import from QR
            root.destroy()
            self.import_qr_config()
            # After import, check if we have endpoints
            if not self.cfg.get("endpoints"):
                root = tk.Tk()
                root.withdraw()
                messagebox.showinfo(
                    "Setup Incomplete",
                    "No endpoint was imported. Please set up an endpoint manually."
                )
                root.destroy()
                self.setup_initial_config_manual()
        else:  # No - manual setup
            root.destroy()
            self.setup_initial_config_manual()
    
    def setup_initial_config_manual(self):
        root = tk.Tk()
        root.withdraw()
        messagebox.showinfo(
            "Manual Setup", 
            "Let's set up your first endpoint.\n"
            "You'll configure:\n"
            "1. POST probe for uploading files\n"
            "2. Pod API for fetching digests and config (optional)"
        )
        
        # Basic endpoint info
        name = simpledialog.askstring("Setup", "Endpoint name:") or "Default"
        device = simpledialog.askstring("Setup", "Device name (optional):") or ""
        
        # POST probe configuration (for uploads)
        messagebox.showinfo("Setup", "First, configure the POST probe for uploading files.")
        key = simpledialog.askstring("Setup", "PROBE_KEY for POST ingest:") or ""
        node = simpledialog.askstring("Setup", "NODE_NAME for POST ingest:") or ""
        probe_id = simpledialog.askstring("Setup", f"PROBE_ID for POST ingest:", initialvalue=DEFAULT_PROBE_ID) or DEFAULT_PROBE_ID
        
        # Screenshot settings
        save_screenshots = messagebox.askyesno("Setup", "Save screenshots locally?")
        folder = ""
        if save_screenshots:
            folder = filedialog.askdirectory(title="Screenshot folder") or ""
        
        # Pod configuration (optional)
        has_pod = messagebox.askyesno("Setup", "Do you have a Pod for queue processing?\n(You can add this later)")
        pod_url = ""
        pod_key = ""
        config_digest_id = ""
        config_tags = "agent-config"
        cache_minutes = "5"
        
        if has_pod:
            messagebox.showinfo("Setup", "Configure the Pod API for fetching digests and agent config.")
            pod_url = simpledialog.askstring(
                "Pod Setup", 
                "Pod API URL (e.g. https://probes-xxx.xyzpulseinfra.com):"
            ) or ""
            pod_key = simpledialog.askstring("Pod Setup", "Pod API Key (X-POD-KEY):") or ""
            
            # Config digest settings
            config_digest_id = simpledialog.askstring(
                "Config", 
                "Agent config digest ID (the digest containing your YAML config):"
            ) or ""
            config_tags = simpledialog.askstring(
                "Config",
                "Tags to search for config and scripts (comma-separated):",
                initialvalue="agent-config"
            ) or "agent-config"
            cache_minutes = simpledialog.askstring(
                "Config",
                "Config cache minutes (0=always refresh, -1=cache forever, 5=refresh every 5 min):",
                initialvalue="5"
            ) or "5"
        
        endpoint = {
            "name": name,
            "DEVICE": device,
            
            # POST probe config (for uploads)
            "PROBE_KEY": key,
            "NODE_NAME": node,
            "PROBE_ID": probe_id,
            
            # Pod config (for fetching)
            "POD_URL": pod_url,
            "POD_KEY": pod_key,
            
            # Config settings
            "CONFIG_DIGEST_ID": config_digest_id,
            "CONFIG_DIGEST_TAGS": config_tags,
            "CONFIG_CACHE_MINUTES": int(cache_minutes),
            
            # Screenshot settings
            "KEEP_SCREENSHOTS": save_screenshots,
            "SCREENSHOT_FOLDER": folder,
        }
        
        self.cfg["endpoints"] = [endpoint]
        self.cfg["last_used_endpoint"] = 0
        self.save_config()
        root.destroy()
    
    def get_current_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if endpoints:
            idx = self.cfg.get("last_used_endpoint", 0)
            if 0 <= idx < len(endpoints):
                return endpoints[idx]
        return None
    
    def get_current_kash_files(self):
        """Get the current Kash Files instance"""
        kash_files = self.cfg.get("kashFiles", [])
        if kash_files:
            idx = self.cfg.get("last_used_kash_files", 0)
            if 0 <= idx < len(kash_files):
                return kash_files[idx]
        return None
    
    def import_qr_config(self):
        """Import configuration from QR code image"""
        root = tk.Tk()
        root.withdraw()
        
        # Select image file
        image_path = filedialog.askopenfilename(
            title="Select QR Code Image",
            filetypes=[
                ("Image files", "*.png *.jpg *.jpeg *.gif *.bmp"),
                ("All files", "*.*")
            ]
        )
        
        if not image_path:
            root.destroy()
            return
        
        # Decode QR
        config = QRConfigImporter.decode_qr_from_image(image_path)
        
        if not config:
            messagebox.showerror("Error", "Could not decode QR code from image.\nTry using 'Paste desktop config JSON' option instead.")
            root.destroy()
            return
        
        # Detect type
        config_type = QRConfigImporter.detect_config_type(config)
        
        if config_type == 'kashFiles':
            # Add Kash Files instance
            name = config.get('name', 'Imported Kash Files')
            if messagebox.askyesno("Import", f"Add Kash Files instance '{name}'?"):
                if 'kashFiles' not in self.cfg:
                    self.cfg['kashFiles'] = []
                self.cfg['kashFiles'].append({
                    'name': name,
                    'url': config.get('url', ''),
                    'key': config.get('key', '')
                })
                self.save_config()
                self.update_kash_files_clients()
                messagebox.showinfo("Success", f"Added Kash Files instance: {name}")
                
        elif config_type == 'mobile_endpoint':
            # Convert mobile config to desktop format
            desktop_config = QRConfigImporter.convert_mobile_to_desktop(config)
            name = desktop_config.get('name', 'Imported')
            
            msg = (
                f"Add endpoint '{name}'?\n\n"
                "Note: This is a basic mobile config.\n"
                "You'll need to add Pod configuration separately\n"
                "using 'Add Pod to endpoint' option."
            )
            
            if messagebox.askyesno("Import Mobile Config", msg):
                # Ask for desktop-specific settings
                desktop_config['KEEP_SCREENSHOTS'] = messagebox.askyesno(
                    "Setup", "Save screenshots locally?"
                )
                if desktop_config['KEEP_SCREENSHOTS']:
                    folder = filedialog.askdirectory(title="Screenshot folder") or ""
                    desktop_config['SCREENSHOT_FOLDER'] = folder
                
                self.cfg['endpoints'].append(desktop_config)
                self.save_config()
                messagebox.showinfo(
                    "Success", 
                    f"Added endpoint: {name}\n\n"
                    "Remember to add Pod configuration for queue processing!"
                )
                
        elif config_type == 'pod':
            # This is a pod sharing QR - use to update current endpoint
            pod_name = config.get('name', 'Unknown Pod')
            msg = (
                f"Pod: {pod_name}\n"
                f"URL: {config.get('entrance_url')}\n\n"
                "Apply this pod configuration to current endpoint?"
            )
            
            if messagebox.askyesno("Pod Configuration", msg):
                self.update_endpoint_pod(config)
                
        else:
            messagebox.showerror("Error", "Unknown QR code configuration type")
        
        root.destroy()
    
    def import_kash_files_qr(self):
        """Import Kash Files instance specifically from QR code"""
        root = tk.Tk()
        root.withdraw()
        
        # Select image file
        image_path = filedialog.askopenfilename(
            title="Select Kash Files QR Code Image",
            filetypes=[
                ("Image files", "*.png *.jpg *.jpeg *.gif *.bmp"),
                ("All files", "*.*")
            ]
        )
        
        if not image_path:
            root.destroy()
            return
        
        # Decode QR
        config = QRConfigImporter.decode_qr_from_image(image_path)
        
        if not config:
            messagebox.showerror("Error", "Could not decode QR code from image")
            root.destroy()
            return
        
        # Verify it's a Kash Files config
        if config.get('type') != 'kashFiles':
            messagebox.showerror(
                "Error", 
                "This QR code does not contain a Kash Files configuration.\n"
                "Kash Files QR codes should have type: 'kashFiles'"
            )
            root.destroy()
            return
        
        # Add the Kash Files instance
        name = config.get('name', 'Imported Kash Files')
        url = config.get('url', '')
        key = config.get('key', '')
        
        # Test connection
        test_client = KashFilesClient({"name": name, "url": url, "key": key})
        test_client.upload_endpoint = "/api/files/upload"
        connection_ok = test_client.test_connection()
        
        if connection_ok:
            status_msg = f"✓ Connection successful to {url}"
        else:
            status_msg = f"⚠ Could not connect to {url}"
        
        msg = (
            f"Add Kash Files instance?\n\n"
            f"Name: {name}\n"
            f"URL: {url}\n"
            f"Key: {key[:10]}...\n\n"
            f"{status_msg}"
        )
        
        if messagebox.askyesno("Import Kash Files", msg):
            if 'kashFiles' not in self.cfg:
                self.cfg['kashFiles'] = []
            
            # Check for duplicates
            existing = [kf['url'] for kf in self.cfg['kashFiles']]
            if url in existing:
                messagebox.showwarning("Warning", f"A Kash Files instance with URL {url} already exists")
            else:
                self.cfg['kashFiles'].append({
                    'name': name,
                    'url': url,
                    'key': key
                })
                self.save_config()
                self.update_kash_files_clients()
                messagebox.showinfo("Success", f"Added Kash Files instance: {name}")
        
        root.destroy()
    
    def update_endpoint_pod(self, pod_config):
        """Update current endpoint with pod configuration from QR"""
        endpoint = self.get_current_endpoint()
        if not endpoint:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", "No current endpoint to update!")
            root.destroy()
            return
        
        # Extract pod settings
        pod_settings = QRConfigImporter.extract_pod_config(pod_config)
        
        # Update endpoint
        endpoint['POD_URL'] = pod_settings['POD_URL']
        endpoint['POD_KEY'] = pod_settings['POD_KEY']
        
        # Save
        self.save_config()
        
        root = tk.Tk()
        root.withdraw()
        messagebox.showinfo(
            "Success",
            f"Updated endpoint '{endpoint['name']}' with pod configuration:\n"
            f"Pod URL: {pod_settings['POD_URL']}"
        )
        root.destroy()
    
    def add_pod_to_endpoint(self):
        """Add or update pod configuration for an endpoint via QR scan"""
        root = tk.Tk() 
        root.withdraw()
        
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            messagebox.showinfo("No Endpoints", "No endpoints configured. Add an endpoint first.")
            root.destroy()
            return
        
        # Select endpoint to update
        choices = "\n".join(f"{i+1}: {ep['name']}" for i, ep in enumerate(endpoints))
        idx_str = simpledialog.askstring(
            "Select Endpoint", 
            f"Which endpoint to update with pod config?\n{choices}",
            parent=root
        )
        
        if not idx_str:
            root.destroy()
            return
        
        try:
            idx = int(idx_str) - 1
            if not (0 <= idx < len(endpoints)):
                raise ValueError("Invalid index")
        except (ValueError, IndexError):
            messagebox.showerror("Error", "Invalid selection", parent=root)
            root.destroy()
            return
        
        # Select QR image
        image_path = filedialog.askopenfilename(
            title="Select Pod QR Code Image",
            filetypes=[
                ("Image files", "*.png *.jpg *.jpeg *.gif *.bmp"),
                ("All files", "*.*")
            ]
        )
        
        if not image_path:
            root.destroy()
            return
        
        # Decode QR
        config = QRConfigImporter.decode_qr_from_image(image_path)
        
        if not config:
            messagebox.showerror("Error", "Could not decode QR code from image")
            root.destroy()
            return
        
        # Verify it's a pod config
        if not ('entrance_url' in config and 'preshared_key' in config):
            messagebox.showerror(
                "Error", 
                "This doesn't appear to be a pod configuration QR.\n"
                "Pod QRs should contain 'entrance_url' and 'preshared_key'."
            )
            root.destroy()
            return
        
        # Update the selected endpoint
        pod_settings = QRConfigImporter.extract_pod_config(config)
        endpoints[idx]['POD_URL'] = pod_settings['POD_URL']
        endpoints[idx]['POD_KEY'] = pod_settings['POD_KEY']
        
        self.save_config()
        
        messagebox.showinfo(
            "Success",
            f"Updated endpoint '{endpoints[idx]['name']}' with pod configuration:\n"
            f"Pod: {config.get('name', 'Unknown')}\n"
            f"URL: {pod_settings['POD_URL']}"
        )
        
        root.destroy()
    
    def edit_raw_config(self):
        """Open raw JSON config for editing"""
        root = tk.Tk()
        root.title("Edit Raw Configuration")
        root.geometry("800x600")
        
        # Create text widget
        text = tk.Text(root, font=("Courier", 10))
        text.pack(fill="both", expand=True, padx=10, pady=10)
        
        # Load current config
        config_json = json.dumps(self.cfg, indent=2)
        text.insert("1.0", config_json)
        
        # Button frame
        button_frame = tk.Frame(root)
        button_frame.pack(pady=10)
        
        def save_raw():
            try:
                new_config = json.loads(text.get("1.0", "end"))
                self.cfg = new_config
                self.save_config()
                self.update_kash_files_clients()
                messagebox.showinfo("Success", "Configuration saved!")
                root.destroy()
            except json.JSONDecodeError as e:
                messagebox.showerror("Error", f"Invalid JSON: {e}")
        
        def cancel():
            root.destroy()
        
        tk.Button(button_frame, text="Save", command=save_raw, width=15).pack(side="left", padx=5)
        tk.Button(button_frame, text="Cancel", command=cancel, width=15).pack(side="left", padx=5)
        
        root.mainloop()
    
    def paste_desktop_config(self):
        """Import a full desktop configuration JSON string"""
        config_json = self.large_text_dialog(
            "Paste Desktop Config",
            "Paste the complete desktop configuration JSON here:"
        )
        
        if not config_json:
            return
        
        try:
            # Parse the pasted JSON
            new_config = json.loads(config_json)
            
            # Validate it has the expected structure
            if 'endpoints' not in new_config:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "Invalid config: missing 'endpoints' array")
                root.destroy()
                return
            
            # Ask what to do
            root = tk.Tk()
            root.withdraw()
            
            choice = messagebox.askyesnocancel(
                "Import Config",
                "Replace entire configuration?\n\n"
                "Yes = Replace all settings\n"
                "No = Merge endpoints only\n"
                "Cancel = Abort"
            )
            
            if choice is None:  # Cancel
                root.destroy()
                return
            elif choice:  # Yes - replace all
                self.cfg = new_config
                messagebox.showinfo("Success", "Configuration replaced!")
            else:  # No - merge endpoints
                # Add new endpoints
                for ep in new_config.get('endpoints', []):
                    # Check for duplicates by name
                    existing_names = [e['name'] for e in self.cfg.get('endpoints', [])]
                    if ep['name'] not in existing_names:
                        self.cfg['endpoints'].append(ep)
                
                # Add new kash files
                if 'kashFiles' in new_config:
                    if 'kashFiles' not in self.cfg:
                        self.cfg['kashFiles'] = []
                    for kf in new_config['kashFiles']:
                        existing_names = [k['name'] for k in self.cfg['kashFiles']]
                        if kf['name'] not in existing_names:
                            self.cfg['kashFiles'].append(kf)
                
                messagebox.showinfo("Success", "Configurations merged!")
            
            self.save_config()
            self.update_kash_files_clients()
            root.destroy()
            
        except json.JSONDecodeError as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Invalid JSON: {e}")
            root.destroy()
        except Exception as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Import failed: {e}")
            root.destroy()
    
    def manage_config(self):
        """Updated config management with new options"""
        root = tk.Tk()
        root.withdraw()
        
        while True:
            # Show current status
            endpoints = self.cfg.get("endpoints", [])
            kash_files = self.cfg.get("kashFiles", [])
            
            menu_text = "=== NODE ENDPOINTS ===\n"
            for i, ep in enumerate(endpoints):
                current = " (CURRENT)" if i == self.cfg.get("last_used_endpoint", 0) else ""
                has_pod = " [POD]" if ep.get('POD_URL') else " [NO POD]"
                menu_text += f"{i+1}: {ep['name']}{current}{has_pod}\n"
            
            menu_text += "\n=== KASH FILES INSTANCES ===\n"
            if kash_files:
                for i, kf in enumerate(kash_files):
                    current = " (CURRENT)" if i == self.cfg.get("last_used_kash_files", 0) else ""
                    menu_text += f"{i+1}: {kf['name']}{current}\n"
            else:
                menu_text += "(None configured)\n"
            
            menu_text += "\n=== QUICK IMPORT ===\n"
            menu_text += "q) Import endpoint from QR code\n"
            menu_text += "w) Import Kash Files from QR code\n"
            menu_text += "p) Add Pod to endpoint (scan Pod QR)\n"
            
            menu_text += "\n=== MANUAL CONFIG ===\n"
            menu_text += "a) Add endpoint manually\n"
            menu_text += "k) Add Kash Files manually\n"
            menu_text += "e) Edit endpoint\n"
            menu_text += "d) Delete endpoint\n"
            menu_text += "s) Switch current endpoint\n"
            menu_text += "f) Switch current Kash Files\n"
            
            menu_text += "\n=== ADVANCED ===\n"
            menu_text += "r) Edit raw config (JSON)\n"
            menu_text += "v) Paste desktop config JSON\n"
            menu_text += "x) Exit\n"
            
            choice = simpledialog.askstring("Manage Config", menu_text, parent=root)
            if not choice or choice.lower() == 'x':
                break
            
            choice = choice.lower().strip()
            
            if choice == 'q':
                self.import_qr_config()
            elif choice == 'w':
                self.import_kash_files_qr()
            elif choice == 'p':
                self.add_pod_to_endpoint()
            elif choice == 'r':
                self.edit_raw_config()
            elif choice == 'v':
                self.paste_desktop_config()
            elif choice == 'a':
                self.add_endpoint()
            elif choice == 'k':
                self.add_kash_files()
            elif choice == 'e':
                self.edit_endpoint()
            elif choice == 'd':
                self.delete_endpoint()
            elif choice == 's':
                self.switch_endpoint()
            elif choice == 'f':
                self.switch_kash_files()
        
        root.destroy()
    
    def add_endpoint(self):
        root = tk.Tk()
        root.withdraw()
        
        # Basic info
        name = simpledialog.askstring("Add Endpoint", "Endpoint name:", parent=root)
        if not name:
            root.destroy()
            return
        
        device = simpledialog.askstring("Add Endpoint", "Device name (optional):", parent=root) or ""
        
        # POST probe config
        messagebox.showinfo("Add Endpoint", "Configure the POST probe for uploading.", parent=root)
        key = simpledialog.askstring("Add Endpoint", "PROBE_KEY for POST ingest:", parent=root) or ""
        node = simpledialog.askstring("Add Endpoint", "NODE_NAME for POST ingest:", parent=root) or ""
        probe_id = simpledialog.askstring(
            "Add Endpoint", "PROBE_ID for POST ingest:", initialvalue=DEFAULT_PROBE_ID, parent=root
        ) or DEFAULT_PROBE_ID

        # Screenshot settings
        save_screenshots = messagebox.askyesno("Add Endpoint", "Save screenshots locally?", parent=root)
        folder = ""
        if save_screenshots:
            folder = filedialog.askdirectory(title="Screenshot folder", parent=root) or ""

        # Pod configuration (optional)
        has_pod = messagebox.askyesno("Add Endpoint", "Configure Pod API now?\n(You can add this later)", parent=root)
        pod_url = ""
        pod_key = ""
        config_digest_id = ""
        config_tags = "agent-config"
        cache_minutes = "5"
        
        if has_pod:
            messagebox.showinfo("Add Endpoint", "Configure the Pod API for fetching digests and config.", parent=root)
            pod_url = simpledialog.askstring(
                "Pod Setup", 
                "Pod API URL (e.g. https://probes-xxx.xyzpulseinfra.com):",
                parent=root
            ) or ""
            pod_key = simpledialog.askstring("Pod Setup", "Pod API Key (X-POD-KEY):", parent=root) or ""
            
            # Config digest
            config_digest_id = simpledialog.askstring(
                "Config",
                "Agent config digest ID:",
                parent=root
            ) or ""
            config_tags = simpledialog.askstring(
                "Config",
                "Tags to search for config and scripts (comma-separated):",
                initialvalue="agent-config",
                parent=root
            ) or "agent-config"
            cache_minutes = simpledialog.askstring(
                "Config",
                "Config cache minutes (0=always refresh, -1=cache forever):",
                initialvalue="5",
                parent=root
            ) or "5"

        endpoint = {
            "name": name,
            "DEVICE": device,
            
            # POST probe config
            "PROBE_KEY": key,
            "NODE_NAME": node,
            "PROBE_ID": probe_id,
            
            # Pod config
            "POD_URL": pod_url,
            "POD_KEY": pod_key,
            
            # Config settings
            "CONFIG_DIGEST_ID": config_digest_id,
            "CONFIG_DIGEST_TAGS": config_tags,
            "CONFIG_CACHE_MINUTES": int(cache_minutes),
            
            # Screenshot settings
            "KEEP_SCREENSHOTS": save_screenshots,
            "SCREENSHOT_FOLDER": folder,
        }
        
        self.cfg["endpoints"].append(endpoint)
        self.save_config()
        root.destroy()
    
    def add_kash_files(self):
        """Add a new Kash Files instance"""
        root = tk.Tk()
        root.withdraw()
        
        name = simpledialog.askstring("Add Kash Files", "Instance name:", parent=root)
        if not name:
            root.destroy()
            return
        
        url = simpledialog.askstring("Add Kash Files", "Kash Files URL:", parent=root)
        if not url:
            root.destroy()
            return
        
        key = simpledialog.askstring("Add Kash Files", "API Key (kf_xxx):", parent=root)
        if not key:
            root.destroy()
            return
        
        # Test connection
        test_client = KashFilesClient({"name": name, "url": url, "key": key})
        test_client.upload_endpoint = "/api/files/upload"
        if test_client.test_connection():
            messagebox.showinfo("Success", "Connection successful!")
        else:
            if not messagebox.askyesno("Warning", "Could not connect. Add anyway?"):
                root.destroy()
                return
        
        if 'kashFiles' not in self.cfg:
            self.cfg['kashFiles'] = []
        
        self.cfg['kashFiles'].append({
            'name': name,
            'url': url,
            'key': key
        })
        
        self.save_config()
        self.update_kash_files_clients()
        root.destroy()
    
    def edit_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Edit", "No endpoints to edit")
            root.destroy()
            return
        
        root = tk.Tk()
        root.withdraw()
        
        choices = "\n".join(f"{i+1}: {ep['name']}" for i, ep in enumerate(endpoints))
        idx_str = simpledialog.askstring("Edit Endpoint", f"Select endpoint:\n{choices}", parent=root)
        
        if not idx_str:
            root.destroy()
            return
            
        try:
            idx = int(idx_str) - 1
            if 0 <= idx < len(endpoints):
                ep = endpoints[idx]
                
                # Basic info
                new_name = simpledialog.askstring("Edit", "Name:", initialvalue=ep.get("name", ""), parent=root)
                if new_name is not None:
                    ep["name"] = new_name
                new_device = simpledialog.askstring("Edit", "Device name (optional):", initialvalue=ep.get("DEVICE", ""), parent=root)
                if new_device is not None:
                    ep["DEVICE"] = new_device
                
                # POST probe
                new_key = simpledialog.askstring("Edit", "PROBE_KEY for POST ingest:", initialvalue=ep.get("PROBE_KEY", ""), parent=root)
                if new_key is not None:
                    ep["PROBE_KEY"] = new_key
                new_node = simpledialog.askstring("Edit", "NODE_NAME for POST ingest:", initialvalue=ep.get("NODE_NAME", ""), parent=root)
                if new_node is not None:
                    ep["NODE_NAME"] = new_node
                new_probe_id = simpledialog.askstring(
                    "Edit", "PROBE_ID for POST ingest:",
                    initialvalue=ep.get("PROBE_ID", DEFAULT_PROBE_ID), parent=root
                )
                if new_probe_id is not None:
                    ep["PROBE_ID"] = new_probe_id or DEFAULT_PROBE_ID
                
                # Screenshot settings
                save_screenshots = messagebox.askyesno("Edit", "Save screenshots locally?", parent=root)
                if save_screenshots:
                    folder = filedialog.askdirectory(title="Screenshot folder", initialdir=ep.get("SCREENSHOT_FOLDER", ""), parent=root)
                    ep["KEEP_SCREENSHOTS"] = True
                    ep["SCREENSHOT_FOLDER"] = folder or ep.get("SCREENSHOT_FOLDER", "")
                else:
                    ep["KEEP_SCREENSHOTS"] = False
                    ep["SCREENSHOT_FOLDER"] = ""
                
                # Pod config
                new_pod_url = simpledialog.askstring(
                    "Edit", "Pod API URL:", 
                    initialvalue=ep.get("POD_URL", ""), parent=root
                )
                if new_pod_url is not None:
                    ep["POD_URL"] = new_pod_url
                new_pod_key = simpledialog.askstring(
                    "Edit", "Pod API Key (X-POD-KEY):",
                    initialvalue=ep.get("POD_KEY", ""), parent=root
                )
                if new_pod_key is not None:
                    ep["POD_KEY"] = new_pod_key
                
                # Config settings
                new_config_id = simpledialog.askstring(
                    "Edit", "Config digest ID:",
                    initialvalue=ep.get("CONFIG_DIGEST_ID", ""), parent=root
                )
                if new_config_id is not None:
                    ep["CONFIG_DIGEST_ID"] = new_config_id
                new_config_tags = simpledialog.askstring(
                    "Edit", "Config and script tags (comma-separated):",
                    initialvalue=ep.get("CONFIG_DIGEST_TAGS", "agent-config"), parent=root
                )
                if new_config_tags is not None:
                    ep["CONFIG_DIGEST_TAGS"] = new_config_tags
                new_cache = simpledialog.askstring(
                    "Edit", "Config cache minutes:",
                    initialvalue=str(ep.get("CONFIG_CACHE_MINUTES", 5)), parent=root
                )
                if new_cache is not None:
                    ep["CONFIG_CACHE_MINUTES"] = int(new_cache)

                self.save_config()
        except (ValueError, IndexError):
            messagebox.showerror("Edit", "Invalid selection", parent=root)
        
        root.destroy()
    
    def delete_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Delete", "No endpoints to delete")
            root.destroy()
            return
        
        root = tk.Tk()
        root.withdraw()
        
        choices = "\n".join(f"{i+1}: {ep['name']}" for i, ep in enumerate(endpoints))
        idx_str = simpledialog.askstring("Delete Endpoint", f"Select endpoint to delete:\n{choices}", parent=root)
        
        if not idx_str:
            root.destroy()
            return
            
        try:
            idx = int(idx_str) - 1
            if 0 <= idx < len(endpoints):
                if messagebox.askyesno("Delete", f"Really delete '{endpoints[idx]['name']}'?", parent=root):
                    del endpoints[idx]
                    if self.cfg["last_used_endpoint"] >= len(endpoints):
                        self.cfg["last_used_endpoint"] = max(0, len(endpoints) - 1)
                    self.save_config()
        except (ValueError, IndexError):
            messagebox.showerror("Delete", "Invalid selection", parent=root)
        
        root.destroy()
    
    def switch_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Switch", "No endpoints configured")
            root.destroy()
            return
        
        root = tk.Tk()
        root.withdraw()
        
        current = self.cfg.get("last_used_endpoint", 0)
        choices = "\n".join(
            f"{i+1}: {ep['name']}" + (" (CURRENT)" if i == current else "")
            for i, ep in enumerate(endpoints)
        )
        idx_str = simpledialog.askstring("Switch Endpoint", f"Select endpoint:\n{choices}", parent=root)
        
        if not idx_str:
            root.destroy()
            return
            
        try:
            idx = int(idx_str) - 1
            if 0 <= idx < len(endpoints):
                self.cfg["last_used_endpoint"] = idx
                self.save_config()
                messagebox.showinfo("Switch", f"Switched to: {endpoints[idx]['name']}", parent=root)
        except (ValueError, IndexError):
            messagebox.showerror("Switch", "Invalid selection", parent=root)
        
        root.destroy()
    
    def switch_kash_files(self):
        """Switch current Kash Files instance"""
        kash_files = self.cfg.get("kashFiles", [])
        if not kash_files:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Switch", "No Kash Files instances configured")
            root.destroy()
            return
        
        root = tk.Tk()
        root.withdraw()
        
        current = self.cfg.get("last_used_kash_files", 0)
        choices = "\n".join(
            f"{i+1}: {kf['name']}" + (" (CURRENT)" if i == current else "")
            for i, kf in enumerate(kash_files)
        )
        idx_str = simpledialog.askstring("Switch Kash Files", f"Select instance:\n{choices}", parent=root)
        
        if not idx_str:
            root.destroy()
            return
        
        try:
            idx = int(idx_str) - 1
            if 0 <= idx < len(kash_files):
                self.cfg["last_used_kash_files"] = idx
                self.save_config()
                messagebox.showinfo("Switch", f"Switched to: {kash_files[idx]['name']}", parent=root)
        except (ValueError, IndexError):
            messagebox.showerror("Switch", "Invalid selection", parent=root)
        
        root.destroy()
    
    def build_tags(self, user_tags, endpoint, filename=None):
        tags = []
        if user_tags:
            tags.extend([tag.strip() for tag in user_tags.split(",") if tag.strip()])
        if endpoint.get("DEVICE"):
            tags.append(endpoint["DEVICE"])
        if filename:
            name_without_ext = os.path.splitext(filename)[0]
            tags.append(name_without_ext)
            if "note" in filename:
                tags.append("note")
            if "screenshot" in filename:
                tags.append("screenshot")
        return ",".join(tags)
    
    def large_text_dialog(self, title, initial_text=""):
        root = tk.Tk()
        root.title(title)
        root.geometry("1280x720")
        result = {"text": None}
        frame = tk.Frame(root)
        frame.pack(fill="both", expand=True, padx=10, pady=10)
        text_widget = tk.Text(frame, font=("Arial", 12))
        text_widget.pack(fill="both", expand=True)
        text_widget.insert("1.0", initial_text)
        text_widget.focus_set()
        button_frame = tk.Frame(root)
        button_frame.pack(pady=10)
        def submit():
            result["text"] = text_widget.get("1.0", "end").strip()
            root.destroy()
        def cancel():
            root.destroy()
        tk.Button(button_frame, text="Upload", command=submit, width=15).pack(side="left", padx=5)
        tk.Button(button_frame, text="Cancel", command=cancel, width=15).pack(side="left", padx=5)
        root.protocol("WM_DELETE_WINDOW", cancel)
        root.mainloop()
        return result["text"]
    
    def take_screenshot(self):
        endpoint = self.get_current_endpoint()
        if not endpoint:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", "No endpoint configured!")
            root.destroy()
            return
        
        fd, tmpfile = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        
        try:
            if sys.platform.startswith('win'):
                # Windows 10+: Use Snip & Sketch
                from PIL import ImageGrab
                
                # Open Snip & Sketch
                subprocess.Popen(["explorer", "ms-screenclip:"])
                
                # Wait for user to take screenshot
                root = tk.Tk()
                root.withdraw()
                messagebox.showinfo(
                    "Screenshot", 
                    "Snip & Sketch is now open.\n\n"
                    "1. Select your screen area\n"
                    "2. The screenshot will be copied to clipboard\n"
                    "3. Click OK below when ready to upload\n\n"
                    "(Or click Cancel to abort)",
                    parent=root
                )
                
                # Grab image from clipboard
                image = ImageGrab.grabclipboard()
                root.destroy()
                
                if image is None:
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showinfo("Info", "No screenshot found in clipboard - upload cancelled")
                    root.destroy()
                    if os.path.exists(tmpfile):
                        os.remove(tmpfile)
                    return
                
                # Save clipboard image to temp file
                image.save(tmpfile, 'PNG')
                
            else:
                # Linux: Use gnome-screenshot
                print(f"[Screenshot] Using temp file: {tmpfile}")
                
                # Run gnome-screenshot and wait for it to complete
                result = subprocess.run(
                    ["gnome-screenshot", "-a", "-f", tmpfile], 
                    capture_output=True,
                    text=True
                )
                
                print(f"[Screenshot] gnome-screenshot exit code: {result.returncode}")
                if result.stderr:
                    print(f"[Screenshot] stderr: {result.stderr}")
                
                # Check if user cancelled (exit code 1 usually means cancelled)
                if result.returncode != 0:
                    print(f"[Screenshot] User cancelled or error occurred")
                    if os.path.exists(tmpfile):
                        os.remove(tmpfile)
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showinfo("Info", "Screenshot cancelled")
                    root.destroy()
                    return
                
                # Wait for file to be written with better checking
                file_ready = False
                for i in range(100):  # 10 seconds max (100 * 0.1)
                    time.sleep(0.1)
                    
                    if os.path.exists(tmpfile):
                        file_size = os.path.getsize(tmpfile)
                        print(f"[Screenshot] Attempt {i+1}: File exists, size: {file_size} bytes")
                        
                        # Check if file has content and isn't still being written
                        if file_size > 0:
                            # Wait a tiny bit more to ensure write is complete
                            time.sleep(0.2)
                            new_size = os.path.getsize(tmpfile)
                            if new_size == file_size:  # File size stable
                                file_ready = True
                                print(f"[Screenshot] File ready: {new_size} bytes")
                                break
                    else:
                        print(f"[Screenshot] Attempt {i+1}: File doesn't exist yet")
                
                if not file_ready:
                    print(f"[Screenshot] Timeout waiting for file")
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showerror("Error", "Screenshot file was not created properly.\nPlease try again.")
                    root.destroy()
                    if os.path.exists(tmpfile):
                        os.remove(tmpfile)
                    return
            
            # Verify we have a valid screenshot file
            if not os.path.exists(tmpfile) or os.path.getsize(tmpfile) == 0:
                root = tk.Tk()
                root.withdraw()
                messagebox.showinfo("Info", "Screenshot file is empty or missing")
                root.destroy()
                if os.path.exists(tmpfile):
                    os.remove(tmpfile)
                return
            
            # Save screenshot locally if configured
            filename = None
            if endpoint.get("KEEP_SCREENSHOTS") and endpoint.get("SCREENSHOT_FOLDER"):
                folder = endpoint["SCREENSHOT_FOLDER"]
                os.makedirs(folder, exist_ok=True)
                filename = f"screenshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
                filepath = os.path.join(folder, filename)
                with open(tmpfile, "rb") as src, open(filepath, "wb") as dst:
                    dst.write(src.read())
                print(f"[Screenshot] Saved locally to: {filepath}")
            else:
                filename = f"screenshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
            
            # Get context and tags
            context = self.large_text_dialog("Screenshot Context")
            if not context:
                root = tk.Tk()
                root.withdraw()
                messagebox.showinfo("Info", "Upload cancelled")
                root.destroy()
                if os.path.exists(tmpfile):
                    os.remove(tmpfile)
                return
            
            user_tags = self.select_tags_dialog()
            
            # Update recent tags
            if user_tags:
                self.update_recent_tags(user_tags)
            
            full_tags = self.build_tags(user_tags, endpoint, filename)
            
            # Upload the screenshot
            with open(tmpfile, "rb") as f:
                file_data = f.read()
            
            print(f"[Screenshot] Uploading {len(file_data)} bytes")
            
            # Ask where to upload
            self.upload_with_choice(filename, file_data, "image/png", full_tags, context)
            
        except ImportError:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror(
                "Error", 
                "PIL (Pillow) not installed!\n\n"
                "Install with: pip install Pillow"
            )
            root.destroy()
        except subprocess.CalledProcessError as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Screenshot tool failed: {e}")
            root.destroy()
        except Exception as e:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", f"Screenshot failed: {e}")
            root.destroy()
        finally:
            # Clean up temp file
            if os.path.exists(tmpfile):
                os.remove(tmpfile)
    
    def quick_note(self):
        note_text = self.large_text_dialog("Quick Note")
        if not note_text:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Info", "Note cancelled")
            root.destroy()
            return
        
        user_tags = self.select_tags_dialog()
        
        # Update recent tags
        if user_tags:
            self.update_recent_tags(user_tags)
        
        filename = f"note_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        endpoint = self.get_current_endpoint()
        if endpoint:
            full_tags = self.build_tags(user_tags, endpoint, filename)
        else:
            full_tags = user_tags
        
        file_data = note_text.encode('utf-8')
        
        # Ask where to upload
        self.upload_with_choice(filename, file_data, "text/plain", full_tags, note_text)
    
    def upload_with_choice(self, filename, file_data, content_type, tags, context):
        """Let user choose where to upload: endpoint, Kash Files, or both"""
        endpoint = self.get_current_endpoint()
        kash_files = self.get_current_kash_files()
        
        if not endpoint and not kash_files:
            root = tk.Tk()
            root.withdraw()
            messagebox.showerror("Error", "No endpoint or Kash Files configured!")
            root.destroy()
            return
        
        root = tk.Tk()
        root.withdraw()
        
        # Build choices
        choices = []
        choice_text = "Where to upload?\n\n"
        
        if endpoint:
            choices.append("endpoint")
            choice_text += f"1) Node Endpoint: {endpoint['name']}\n"
        
        if kash_files:
            choices.append("kashfiles")
            offset = 1 if endpoint else 0
            choice_text += f"{offset + 1}) Kash Files: {kash_files['name']}\n"
        
        if endpoint and kash_files:
            choices.append("both")
            choice_text += "3) Both (file + caption as separate digests)\n"
        
        choice_text += "\nEnter number or press Cancel:"
        
        # If only one option, don't ask
        if len(choices) == 1:
            if choices[0] == "endpoint":
                self.upload_file(filename, file_data, content_type, tags, context, endpoint)
            else:  # kashfiles
                self.upload_to_kash_files_with_result(filename, file_data, content_type, tags, context)
        else:
            # Ask user
            choice_str = simpledialog.askstring("Upload Destination", choice_text, parent=root)
            
            if choice_str:
                try:
                    choice_idx = int(choice_str) - 1
                    if 0 <= choice_idx < len(choices):
                        selected = choices[choice_idx]
                        
                        if selected == "endpoint":
                            # Just upload to endpoint
                            self.upload_file(filename, file_data, content_type, tags, context, endpoint)
                            
                        elif selected == "kashfiles":
                            # Just upload to Kash Files
                            self.upload_to_kash_files_with_result(filename, file_data, content_type, tags, context)
                            
                        elif selected == "both":
                            # Upload to both - special workflow
                            # 1. Upload file to Kash Files first
                            file_url = self.upload_to_kash_files_with_result(filename, file_data, content_type, tags, context)
                            
                            if file_url:
                                # 2. Upload the original file to endpoint
                                self.upload_file(filename, file_data, content_type, tags, context, endpoint)
                                
                                # 3. Create and upload a caption note with the link
                                caption_filename = f"caption_{filename.rsplit('.', 1)[0]}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
                                
                                # Build caption content with link
                                caption_content = f"File: {filename}\nLink: {file_url}\n\n{context}"
                                caption_data = caption_content.encode('utf-8')
                                
                                # Upload the caption as a separate digest with same tags
                                self.upload_file(caption_filename, caption_data, "text/plain", tags, caption_content, endpoint)
                                
                                messagebox.showinfo(
                                    "Success", 
                                    f"Uploaded to both!\n\n"
                                    f"• File uploaded to endpoint\n"
                                    f"• File uploaded to Kash Files\n"
                                    f"• Caption with link uploaded to endpoint"
                                )
                            else:
                                messagebox.showwarning("Partial Success", "File uploaded to endpoint but Kash Files upload failed")
                                
                except (ValueError, IndexError):
                    messagebox.showerror("Error", "Invalid selection", parent=root)
        
        root.destroy()
    
    def upload_file(self, filename, file_data, content_type, tags, context, endpoint):
        """Upload file using POST probe (unchanged - still uses API bastion)"""
        try:
            url = f"https://probes-{endpoint['NODE_NAME']}.xyzpulseinfra.com/api/probes/{endpoint['PROBE_ID']}/run"
            payload = {
                "file": {
                    "content": base64.b64encode(file_data).decode('utf-8'),
                    "filename": filename,
                    "content_type": content_type
                },
                "tags": tags,
                "device": endpoint.get("DEVICE", ""),
                "context_prompt": context
            }
            headers = {
                "Content-Type": "application/json",
                "X-PROBE-KEY": endpoint["PROBE_KEY"]
            }
            response = requests.post(url, json=payload, headers=headers)
            if response.status_code == 200:
                if self.headless:
                    print(f"[KashStash] Upload to endpoint completed! Tags: {tags}")
                else:
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showinfo("Success", f"Upload to endpoint completed!\nTags: {tags}")
                    root.destroy()
            else:
                if self.headless:
                    print(f"[KashStash] Upload to endpoint failed: {response.status_code}")
                else:
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showerror("Error", f"Upload to endpoint failed: {response.status_code}")
                    root.destroy()
        except Exception as e:
            if self.headless:
                print(f"[KashStash] Upload to endpoint error: {e}")
            else:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", f"Upload to endpoint error: {e}")
                root.destroy()
    
    def upload_to_kash_files_with_result(self, filename, file_data, content_type, tags, description):
        """Upload file to Kash Files instance and return the URL"""
        kash_files = self.get_current_kash_files()
        if not kash_files:
            if not self.headless:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", "No Kash Files instance configured!")
                root.destroy()
            return None
        
        try:
            # Make the request directly with corrected endpoint
            endpoint = f"{kash_files['url']}/api/files/upload"
            
            files = {
                'file': (filename, file_data, content_type)
            }
            data = {
                'tags': tags,
                'description': description
            }
            headers = {
                'x-upload-key': f'{kash_files["key"]}'
            }
            
            response = requests.post(endpoint, files=files, data=data, headers=headers)
            response.raise_for_status()
            
            result = response.json()
            
            # Check if upload was successful
            if not result.get('ok'):
                if not self.headless:
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showerror("Error", "Kash Files upload failed")
                    root.destroy()
                return None
            
            # Extract the download URL
            download_path = result.get('download', '')
            if not download_path:
                if not self.headless:
                    root = tk.Tk()
                    root.withdraw()
                    messagebox.showerror("Error", "No download URL in response")
                    root.destroy()
                return None
            
            # Construct full URL
            file_url = f"{kash_files['url']}{download_path}"
            
            if self.headless:
                print(f"[KashStash] Upload to Kash Files completed! URL: {file_url}")
            else:
                print(f"[KashStash] Kash Files upload successful: {file_url}")
            
            return file_url
            
        except Exception as e:
            if self.headless:
                print(f"[KashStash] Upload to Kash Files failed: {e}")
            else:
                root = tk.Tk()
                root.withdraw()
                messagebox.showerror("Error", f"Upload to Kash Files failed: {e}")
                root.destroy()
            return None

    def upload_to_kash_files(self, filename, file_data, content_type, tags, description):
        """Upload file to Kash Files instance (original method for backward compatibility)"""
        result = self.upload_to_kash_files_with_result(filename, file_data, content_type, tags, description)
        if result and not self.headless:
            root = tk.Tk()
            root.withdraw()
            messagebox.showinfo("Success", f"Upload to Kash Files completed!\nURL: {result}")
            root.destroy()
    
    def start_agent_monitor(self):
        """Starts the agent monitoring/queue boss."""
        def endpoint_getter():
            return self.get_current_endpoint()
        
        self._queue_boss = QueueBoss(endpoint_getter)
        
        if self.headless:
            # In headless mode, start queue boss (spawns daemon threads)
            print("[KashStash] Starting agent monitor in headless mode...")
            endpoint = self.get_current_endpoint()
            if endpoint:
                print(f"[KashStash] Using endpoint: {endpoint['name']}")
                print(f"[KashStash] Config digest: {endpoint.get('CONFIG_DIGEST_ID')} (tags: {endpoint.get('CONFIG_DIGEST_TAGS')})")
                print(f"[KashStash] Cache: {endpoint.get('CONFIG_CACHE_MINUTES')} minutes")
            else:
                print("[KashStash] WARNING: No endpoint configured!")
            self._queue_boss.start()
            print("[KashStash] Queue boss started (running in background threads)")
        else:
            # In GUI mode, run in background thread (non-blocking)
            t = threading.Thread(target=self._queue_boss.start, name="QueueBossAgent", daemon=True)
            t.start()
            print("[KashStash] Agent monitor started in background.")


def create_tray_icon(app):
    # Windows fix: Run GUI operations in separate threads to avoid blocking
    def on_screenshot(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.take_screenshot, daemon=True).start()
        else:
            app.take_screenshot()
    
    def on_note(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.quick_note, daemon=True).start()
        else:
            app.quick_note()
    
    def on_upload_file(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.upload_file_with_note, daemon=True).start()
        else:
            app.upload_file_with_note()
    
    def on_config(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.manage_config, daemon=True).start()
        else:
            app.manage_config()
    
    def on_switch(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.switch_endpoint, daemon=True).start()
        else:
            app.switch_endpoint()
    
    def on_node_portal(icon, item):
        if sys.platform.startswith('win'):
            threading.Thread(target=app.open_node_portal, daemon=True).start()
        else:
            app.open_node_portal()
    
    def on_blog(icon, item):
        app.open_blog()  # This just opens browser, no GUI needed
    
    def on_portal(icon, item):
        app.open_portal()  # This just opens browser, no GUI needed
    
    def on_exit(icon, item):
        icon.stop()
    
    logo_path = resource_path('kash_stash_logo.png')
    image = Image.open(logo_path)
    image = image.resize((64, 64))
    current_endpoint = app.get_current_endpoint()
    current_name = current_endpoint['name'] if current_endpoint else "None"
    
    # Create Go To submenu
    go_to_menu = pystray.Menu(
        pystray.MenuItem("My Node", on_node_portal),
        pystray.MenuItem("Blog", on_blog),
        pystray.MenuItem("Portal", on_portal)
    )
    
    menu = pystray.Menu(
        pystray.MenuItem(f"Current: {current_name}", None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Take Screenshot", on_screenshot),
        pystray.MenuItem("Quick Note", on_note),
        pystray.MenuItem("Upload File", on_upload_file),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Go To", go_to_menu),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Switch Endpoint", on_switch),
        pystray.MenuItem("Manage Config", on_config),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Exit", on_exit)
    )
    
    icon = pystray.Icon("Kash Stash", image, "Kash Stash", menu)
    try:
        icon.run()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Kash Stash - Screenshot and note uploader with queue processing")
    parser.add_argument("--headless", action="store_true", 
                       help="Run in headless mode (no GUI, just queue boss)")
    args = parser.parse_args()
    
    app = KashStash(headless=args.headless)
    
    if args.headless:
        # Headless mode: start the agent monitor (spawns daemon threads) and keep main thread alive
        print("[KashStash] Running in headless mode (Ctrl+C to stop)")
        app.start_agent_monitor()
        
        # Keep main thread alive indefinitely
        try:
            while True:
                time.sleep(3600)  # Sleep for an hour at a time
        except KeyboardInterrupt:
            print("\n[KashStash] Shutting down...")
            sys.exit(0)
    else:
        # GUI mode: start agent monitor in background, then create tray icon
        app.start_agent_monitor()
        create_tray_icon(app)