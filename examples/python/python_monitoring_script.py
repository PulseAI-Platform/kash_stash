#!/usr/bin/env python3
import json
import base64
import platform
import psutil
import socket
from datetime import datetime

def main():
    try:
        # Collect key metrics
        cpu = psutil.cpu_percent(interval=1)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        # Determine health status
        tags = ["sysmon", "py", socket.gethostname()]
        alerts = []
        
        if cpu > 90:
            tags.append("cpu-crit")
            alerts.append(f"CPU:{cpu}%")
        elif cpu > 75:
            tags.append("cpu-warn")
        
        if mem.percent > 90:
            tags.append("mem-crit")
            alerts.append(f"MEM:{mem.percent}%")
        elif mem.percent > 80:
            tags.append("mem-warn")
        
        if disk.percent > 95:
            tags.append("disk-crit")
            alerts.append(f"DISK:{disk.percent}%")
        elif disk.percent > 85:
            tags.append("disk-warn")
        
        # Overall status
        if any("crit" in t for t in tags):
            tags.append("critical")
        elif any("warn" in t for t in tags):
            tags.append("warning")
        else:
            tags.append("healthy")
        
        # Format compact output
        lines = [
            f"[{datetime.utcnow().strftime('%Y-%m-%d %H:%M')}] {socket.gethostname()}",
            f"CPU: {cpu}% | MEM: {mem.percent}% ({round(mem.available/(1024**3),1)}GB free) | DISK: {disk.percent}%"
        ]
        
        if alerts:
            lines.append("ALERTS: " + " | ".join(alerts))
        
        # Get top process if CPU/MEM high
        if cpu > 75 or mem.percent > 80:
            procs = []
            for p in psutil.process_iter(['name', 'cpu_percent', 'memory_percent']):
                try:
                    procs.append(p.info)
                except:
                    pass
            
            if procs:
                top_cpu = max(procs, key=lambda x: x['cpu_percent'])
                top_mem = max(procs, key=lambda x: x['memory_percent'])
                lines.append(f"Top CPU: {top_cpu['name'][:20]} ({top_cpu['cpu_percent']}%)")
                lines.append(f"Top MEM: {top_mem['name'][:20]} ({top_mem['memory_percent']:.1f}%)")
        
        # Build result
        content = base64.b64encode("\n".join(lines).encode()).decode()
        
        result = {
            "tags": ",".join(tags),
            "content": content
        }
        
        print(json.dumps(result))
        return 0
        
    except Exception as e:
        # Error handling
        error_b64 = base64.b64encode(f"Monitor error: {e}".encode()).decode()
        result = {
            "tags": f"sysmon-error,py,{socket.gethostname()}",
            "content": error_b64
        }
        print(json.dumps(result))
        return 1

if __name__ == "__main__":
    exit(main())