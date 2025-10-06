#!/usr/bin/env python3
import os
import sys
import json
import base64
import subprocess
import tempfile
import time
import requests
from datetime import datetime
from PIL import Image
import pystray
import tkinter as tk
from tkinter import simpledialog, messagebox, filedialog
from queue_boss import QueueBoss
import threading

CONFIG_PATH = os.path.expanduser("~/.kash_stash_config.json")

DEFAULT_PROBE_ID = "29"
DEFAULT_DIGEST_PROBE_ID = "7"
DEFAULT_LISTDIGESTS_PROBE_ID = "6"

class KashStash:
    def __init__(self):
        self.cfg = self.load_config()
        if not self.cfg.get("endpoints"):
            self.setup_initial_config()
    
    def load_config(self):
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH) as f:
                return json.load(f)
        return {"endpoints": [], "last_used_endpoint": 0}
    
    def save_config(self):
        with open(CONFIG_PATH, "w") as f:
            json.dump(self.cfg, f, indent=2)
    
    def setup_initial_config(self):
        root = tk.Tk()
        root.withdraw()
        messagebox.showinfo(
            "Kash Stash", "First run! Let's set up your first endpoint.\n"
                          "You'll set a primary \"ingest\" probe. The digest-fetch endpoints are optional and can be left blank."
        )
        
        name = simpledialog.askstring("Setup", "Endpoint name:") or "Default"
        key = simpledialog.askstring("Setup", "PROBE_KEY for POST ingest:") or ""
        node = simpledialog.askstring("Setup", "NODE_NAME for POST ingest:") or ""
        probe_id = simpledialog.askstring("Setup", f"PROBE_ID for POST ingest:", initialvalue=DEFAULT_PROBE_ID) or DEFAULT_PROBE_ID
        device = simpledialog.askstring("Setup", "Device name:") or ""
        
        save_screenshots = messagebox.askyesno("Setup", "Save screenshots locally?")
        folder = ""
        if save_screenshots:
            folder = filedialog.askdirectory(title="Screenshot folder") or ""
        
        # Config template digest (used by agent)
        config_digest_id = simpledialog.askstring(
            "Config Digest",
            "Config digest id (the digest id from your node where the config template is stored):"
        ) or ""
        config_digest_node_name = simpledialog.askstring(
            "Config Digest",
            f"NODE_NAME for config digest (leave blank to use POST ingest node '{node}'):"
        ) or "" or node

        # Optional: single-digest GET probe
        digest_probe_id = simpledialog.askstring(
            "OPTIONAL", "PROBE_ID for GET single digest (blank=skip):", initialvalue=DEFAULT_DIGEST_PROBE_ID
        ) or ""
        digest_probe_key = simpledialog.askstring("OPTIONAL", "PROBE_KEY for GET single digest (blank=skip):") or ""
        digest_node_name = simpledialog.askstring(
            "OPTIONAL", f"NODE_NAME for GET single digest (blank=use ingest node '{node}'):"
        ) or "" or node

        # Optional: list-digests GET probe
        listdigests_probe_id = simpledialog.askstring(
            "OPTIONAL", "PROBE_ID for LIST digests (blank=skip):", initialvalue=DEFAULT_LISTDIGESTS_PROBE_ID
        ) or ""
        listdigests_probe_key = simpledialog.askstring("OPTIONAL", "PROBE_KEY for LIST digests (blank=skip):") or ""
        listdigests_node_name = simpledialog.askstring(
            "OPTIONAL", f"NODE_NAME for LIST digests (blank=use ingest node '{node}'):"
        ) or "" or node

        endpoint = {
            "name": name,
            "PROBE_KEY": key,
            "NODE_NAME": node,
            "PROBE_ID": probe_id,
            "DEVICE": device,
            "KEEP_SCREENSHOTS": save_screenshots,
            "SCREENSHOT_FOLDER": folder,

            # NEW:
            "CONFIG_DIGEST_ID": config_digest_id,
            "CONFIG_DIGEST_NODE_NAME": config_digest_node_name or node,

            "DIGEST_PROBE_ID": digest_probe_id,
            "DIGEST_PROBE_KEY": digest_probe_key,
            "DIGEST_NODE_NAME": digest_node_name or node,

            "LISTDIGESTS_PROBE_ID": listdigests_probe_id,
            "LISTDIGESTS_PROBE_KEY": listdigests_probe_key,
            "LISTDIGESTS_NODE_NAME": listdigests_node_name or node,
        }
        
        self.cfg["endpoints"] = [endpoint]
        self.cfg["last_used_endpoint"] = 0
        self.save_config()
        root.destroy()
    
    def manage_config(self):
        root = tk.Tk()
        root.withdraw()
        
        while True:
            endpoints = self.cfg.get("endpoints", [])
            menu_text = "Current endpoints:\n"
            for i, ep in enumerate(endpoints):
                current = " (CURRENT)" if i == self.cfg.get("last_used_endpoint", 0) else ""
                menu_text += f"{i+1}: {ep['name']}{current}\n"
            
            menu_text += "\nOptions:\na) Add endpoint\ne) Edit endpoint\nd) Delete endpoint\ns) Switch current endpoint\nq) Quit\n"
            
            choice = simpledialog.askstring("Manage Config", menu_text, parent=root)
            if not choice or choice.lower() == 'q':
                break
                
            choice = choice.lower().strip()
            
            if choice == 'a':
                self.add_endpoint()
            elif choice == 'e':
                self.edit_endpoint()
            elif choice == 'd':
                self.delete_endpoint()
            elif choice == 's':
                self.switch_endpoint()
        
        root.destroy()
    
    def add_endpoint(self):
        root = tk.Tk()
        root.withdraw()
        
        name = simpledialog.askstring("Add Endpoint", "Endpoint name:", parent=root)
        if not name:
            root.destroy()
            return
            
        key = simpledialog.askstring("Add Endpoint", "PROBE_KEY for POST ingest:", parent=root) or ""
        node = simpledialog.askstring("Add Endpoint", "NODE_NAME for POST ingest:", parent=root) or ""
        probe_id = simpledialog.askstring(
            "Add Endpoint", "PROBE_ID for POST ingest:", initialvalue=DEFAULT_PROBE_ID, parent=root
        ) or DEFAULT_PROBE_ID
        device = simpledialog.askstring("Add Endpoint", "Device name:", parent=root) or ""

        save_screenshots = messagebox.askyesno("Add Endpoint", "Save screenshots locally?", parent=root)
        folder = ""
        if save_screenshots:
            folder = filedialog.askdirectory(title="Screenshot folder", parent=root) or ""

        # Config template digest (used by agent)
        config_digest_id = simpledialog.askstring(
            "Config Digest",
            "Config digest id (the digest id from your node where the config template is stored):",
            parent=root
        ) or ""
        config_digest_node_name = simpledialog.askstring(
            "Config Digest",
            f"NODE_NAME for config digest (leave blank to use POST ingest node '{node}'):",
            parent=root
        ) or "" or node

        digest_probe_id = simpledialog.askstring(
            "OPTIONAL", "PROBE_ID for GET single digest (blank=skip):", initialvalue=DEFAULT_DIGEST_PROBE_ID, parent=root
        ) or ""
        digest_probe_key = simpledialog.askstring("OPTIONAL", "PROBE_KEY for GET single digest (blank=skip):", parent=root) or ""
        digest_node_name = simpledialog.askstring(
            "OPTIONAL", f"NODE_NAME for GET single digest (blank=use ingest node '{node}'):", parent=root
        ) or "" or node
        
        listdigests_probe_id = simpledialog.askstring(
            "OPTIONAL", "PROBE_ID for LIST digests (blank=skip):", initialvalue=DEFAULT_LISTDIGESTS_PROBE_ID, parent=root
        ) or ""
        listdigests_probe_key = simpledialog.askstring("OPTIONAL", "PROBE_KEY for LIST digests (blank=skip):", parent=root) or ""
        listdigests_node_name = simpledialog.askstring(
            "OPTIONAL", f"NODE_NAME for LIST digests (blank=use ingest node '{node}'):", parent=root
        ) or "" or node

        endpoint = {
            "name": name,
            "PROBE_KEY": key,
            "NODE_NAME": node,
            "PROBE_ID": probe_id,
            "DEVICE": device,
            "KEEP_SCREENSHOTS": save_screenshots,
            "SCREENSHOT_FOLDER": folder,

            "CONFIG_DIGEST_ID": config_digest_id,
            "CONFIG_DIGEST_NODE_NAME": config_digest_node_name or node,

            "DIGEST_PROBE_ID": digest_probe_id,
            "DIGEST_PROBE_KEY": digest_probe_key,
            "DIGEST_NODE_NAME": digest_node_name or node,

            "LISTDIGESTS_PROBE_ID": listdigests_probe_id,
            "LISTDIGESTS_PROBE_KEY": listdigests_probe_key,
            "LISTDIGESTS_NODE_NAME": listdigests_node_name or node,
        }
        
        self.cfg["endpoints"].append(endpoint)
        self.save_config()
        root.destroy()
    
    def edit_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            messagebox.showinfo("Edit", "No endpoints to edit")
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
                new_name = simpledialog.askstring("Edit", "Name:", initialvalue=ep.get("name", ""), parent=root)
                if new_name is not None:
                    ep["name"] = new_name
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
                new_device = simpledialog.askstring("Edit", "Device name:", initialvalue=ep.get("DEVICE", ""), parent=root)
                if new_device is not None:
                    ep["DEVICE"] = new_device
                save_screenshots = messagebox.askyesno("Edit", "Save screenshots locally?", parent=root)
                if save_screenshots:
                    folder = filedialog.askdirectory(title="Screenshot folder", initialdir=ep.get("SCREENSHOT_FOLDER", ""), parent=root)
                    ep["KEEP_SCREENSHOTS"] = True
                    ep["SCREENSHOT_FOLDER"] = folder or ep.get("SCREENSHOT_FOLDER", "")
                else:
                    ep["KEEP_SCREENSHOTS"] = False
                    ep["SCREENSHOT_FOLDER"] = ""

                # Config template digest (used by agent)
                config_digest_id = simpledialog.askstring(
                    "Config Digest",
                    "Config digest id (the digest id from your node where the config template is stored):",
                    initialvalue=ep.get("CONFIG_DIGEST_ID", ""),
                    parent=root
                ) or ""
                config_digest_node_name = simpledialog.askstring(
                    "Config Digest",
                    f"NODE_NAME for config digest (leave blank to use POST ingest node '{ep.get('NODE_NAME','')}'):",
                    initialvalue=ep.get("CONFIG_DIGEST_NODE_NAME", ep.get("NODE_NAME", "")),
                    parent=root
                ) or "" or ep.get("NODE_NAME", "")
                ep["CONFIG_DIGEST_ID"] = config_digest_id
                ep["CONFIG_DIGEST_NODE_NAME"] = config_digest_node_name or ep.get("NODE_NAME", "")

                digest_probe_id = simpledialog.askstring(
                    "Edit (Optional)", "PROBE_ID for GET single digest (blank=skip):",
                    initialvalue=ep.get("DIGEST_PROBE_ID", DEFAULT_DIGEST_PROBE_ID), parent=root
                )
                digest_probe_key = simpledialog.askstring(
                    "Edit (Optional)", "PROBE_KEY for GET single digest (blank=skip):",
                    initialvalue=ep.get("DIGEST_PROBE_KEY", ""), parent=root
                )
                digest_node_name = simpledialog.askstring(
                    "Edit (Optional)", f"NODE_NAME for GET single digest (blank=use ingest node '{ep.get('NODE_NAME','')}'):",
                    initialvalue=ep.get("DIGEST_NODE_NAME", ep.get("NODE_NAME", "")), parent=root
                )
                ep["DIGEST_PROBE_ID"] = digest_probe_id or ""
                ep["DIGEST_PROBE_KEY"] = digest_probe_key or ""
                ep["DIGEST_NODE_NAME"] = digest_node_name or ep.get("NODE_NAME", "")

                listdigests_probe_id = simpledialog.askstring(
                    "Edit (Optional)", "PROBE_ID for LIST digests (blank=skip):",
                    initialvalue=ep.get("LISTDIGESTS_PROBE_ID", DEFAULT_LISTDIGESTS_PROBE_ID), parent=root
                )
                listdigests_probe_key = simpledialog.askstring(
                    "Edit (Optional)", "PROBE_KEY for LIST digests (blank=skip):",
                    initialvalue=ep.get("LISTDIGESTS_PROBE_KEY", ""), parent=root
                )
                listdigests_node_name = simpledialog.askstring(
                    "Edit (Optional)", f"NODE_NAME for LIST digests (blank=use ingest node '{ep.get('NODE_NAME','')}'):",
                    initialvalue=ep.get("LISTDIGESTS_NODE_NAME", ep.get("NODE_NAME", "")), parent=root
                )
                ep["LISTDIGESTS_PROBE_ID"] = listdigests_probe_id or ""
                ep["LISTDIGESTS_PROBE_KEY"] = listdigests_probe_key or ""
                ep["LISTDIGESTS_NODE_NAME"] = listdigests_node_name or ep.get("NODE_NAME", "")

                self.save_config()
        except (ValueError, IndexError):
            messagebox.showerror("Edit", "Invalid selection", parent=root)
        
        root.destroy()
    
    def delete_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if not endpoints:
            messagebox.showinfo("Delete", "No endpoints to delete")
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
            messagebox.showinfo("Switch", "No endpoints configured")
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
    
    def get_current_endpoint(self):
        endpoints = self.cfg.get("endpoints", [])
        if endpoints:
            idx = self.cfg.get("last_used_endpoint", 0)
            if 0 <= idx < len(endpoints):
                return endpoints[idx]
        return None
    
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
            messagebox.showerror("Error", "No endpoint configured!")
            return
        fd, tmpfile = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        try:
            subprocess.run(["gnome-screenshot", "-a", "-f", tmpfile], check=True)
            for _ in range(50):  # 5 seconds max
                time.sleep(0.1)
                if os.path.exists(tmpfile) and os.path.getsize(tmpfile) > 0:
                    break
            else:
                messagebox.showinfo("Info", "Screenshot cancelled or failed")
                return
            filename = None
            if endpoint.get("KEEP_SCREENSHOTS") and endpoint.get("SCREENSHOT_FOLDER"):
                folder = endpoint["SCREENSHOT_FOLDER"]
                os.makedirs(folder, exist_ok=True)
                filename = f"screenshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
                filepath = os.path.join(folder, filename)
                with open(tmpfile, "rb") as src, open(filepath, "wb") as dst:
                    dst.write(src.read())
            else:
                filename = f"screenshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
            context = self.large_text_dialog("Screenshot Context")
            if not context:
                messagebox.showinfo("Info", "Upload cancelled")
                return
            root = tk.Tk()
            root.withdraw()
            user_tags = simpledialog.askstring("Tags", "Enter tags (comma separated):") or ""
            root.destroy()
            full_tags = self.build_tags(user_tags, endpoint, filename)
            with open(tmpfile, "rb") as f:
                file_data = f.read()
            self.upload_file(filename, file_data, "image/png", full_tags, context, endpoint)
        except subprocess.CalledProcessError:
            messagebox.showerror("Error", "Screenshot tool failed. Install and Open gnome-screenshot.")
        except Exception as e:
            messagebox.showerror("Error", f"Screenshot failed: {e}")
        finally:
            if os.path.exists(tmpfile):
                os.remove(tmpfile)
    
    def quick_note(self):
        endpoint = self.get_current_endpoint()
        if not endpoint:
            messagebox.showerror("Error", "No endpoint configured!")
            return
        note_text = self.large_text_dialog("Quick Note")
        if not note_text:
            messagebox.showinfo("Info", "Note cancelled")
            return
        root = tk.Tk()
        root.withdraw()
        user_tags = simpledialog.askstring("Tags", "Enter tags (comma separated):") or ""
        root.destroy()
        filename = f"note_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
        full_tags = self.build_tags(user_tags, endpoint, filename)
        file_data = note_text.encode('utf-8')
        self.upload_file(filename, file_data, "text/plain", full_tags, note_text, endpoint)
    
    def upload_file(self, filename, file_data, content_type, tags, context, endpoint):
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
                messagebox.showinfo("Success", f"Upload completed!\nTags: {tags}")
            else:
                messagebox.showerror("Error", f"Upload failed: {response.status_code}")
        except Exception as e:
            messagebox.showerror("Error", f"Upload error: {e}")

    def get_digest_fetch_conf(self):
        ep = self.get_current_endpoint() or {}
        if ep.get("DIGEST_PROBE_ID") and ep.get("DIGEST_PROBE_KEY"):
            return {
                "probe_id": ep["DIGEST_PROBE_ID"] or DEFAULT_DIGEST_PROBE_ID,
                "probe_key": ep["DIGEST_PROBE_KEY"],
                "node_name": ep.get("DIGEST_NODE_NAME", ep.get("NODE_NAME", ""))
            }
        return None

    def get_listdigests_conf(self):
        ep = self.get_current_endpoint() or {}
        if ep.get("LISTDIGESTS_PROBE_ID") and ep.get("LISTDIGESTS_PROBE_KEY"):
            return {
                "probe_id": ep["LISTDIGESTS_PROBE_ID"] or DEFAULT_LISTDIGESTS_PROBE_ID,
                "probe_key": ep["LISTDIGESTS_PROBE_KEY"],
                "node_name": ep.get("LISTDIGESTS_NODE_NAME", ep.get("NODE_NAME", ""))
            }
        return None

    def get_config_digest_conf(self):
        ep = self.get_current_endpoint() or {}
        if ep.get("CONFIG_DIGEST_ID"):
            return {
                "digest_id": ep["CONFIG_DIGEST_ID"],
                "node_name": ep.get("CONFIG_DIGEST_NODE_NAME", ep.get("NODE_NAME", ""))
            }
        return None
    def start_agent_monitor(self):
        """
        Starts the agent monitoring/queue boss in a background thread.
        """
        # Define the endpoint getter so that QueueBoss always sees the latest endpoint/config
        def endpoint_getter():
            endpoint = self.get_current_endpoint()
            return endpoint
        self._queue_boss = QueueBoss(endpoint_getter)
        t = threading.Thread(target=self._queue_boss.start, name="QueueBossAgent", daemon=True)
        t.start()
        print("[KashStash] Agent monitor started.")



def create_tray_icon(app):
    def on_screenshot(icon, item):
        app.take_screenshot()
    def on_note(icon, item):
        app.quick_note()
    def on_config(icon, item):
        app.manage_config()
    def on_switch(icon, item):
        app.switch_endpoint()
    def on_exit(icon, item):
        icon.stop()
    image = Image.new('RGB', (64, 64), color='green')
    current_endpoint = app.get_current_endpoint()
    current_name = current_endpoint['name'] if current_endpoint else "None"
    menu = pystray.Menu(
        pystray.MenuItem(f"Current: {current_name}", None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Take Screenshot", on_screenshot),
        pystray.MenuItem("Quick Note", on_note),
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
    app = KashStash()
    app.start_agent_monitor()
    create_tray_icon(app)