#!/usr/bin/env python3
import sys
import os
import base64
import re
import json
from urllib.parse import urlparse

def parse_input():
    """Read input from file argument"""
    if len(sys.argv) < 2:
        return ""
    
    input_file = sys.argv[1]
    if not os.path.isfile(input_file):
        return ""
    
    with open(input_file, 'r') as f:
        return f.read()

def check_url(url):
    """Check single URL for suspicious patterns"""
    suspicious_patterns = [
        (r'bit\.ly|tinyurl|goo\.gl|short\.link', 'shortener'),
        (r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', 'ip-address'),
        (r'\.exe|\.zip|\.rar|\.msi', 'download'),
        (r'phishing|malware|hack|virus', 'malicious-keyword'),
        (r'[0-9a-f]{32}', 'hash-pattern'),
    ]
    
    for pattern, threat_type in suspicious_patterns:
        if re.search(pattern, url, re.IGNORECASE):
            return threat_type
    return None

def process_urls(input_text):
    """Process URL list and generate concise report"""
    if not input_text:
        return "status: error\nmessage: No input provided", 0, 0
    
    lines = input_text.strip().split('\n')
    
    total = 0
    suspicious = []
    domains = set()
    threats = {}
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        total += 1
        
        # Extract domain
        try:
            if not line.startswith(('http://', 'https://')):
                line = f'http://{line}'
            parsed = urlparse(line)
            domain = parsed.netloc or parsed.path.split('/')[0]
            if domain:
                domains.add(domain)
        except:
            pass
        
        # Check for threats
        threat = check_url(line)
        if threat:
            suspicious.append(f"{line[:50]}:{threat}")
            threats[threat] = threats.get(threat, 0) + 1
    
    # Build output as key-value pairs
    output_lines = []
    output_lines.append(f"total_urls: {total}")
    output_lines.append(f"unique_domains: {len(domains)}")
    output_lines.append(f"suspicious_count: {len(suspicious)}")
    output_lines.append(f"clean_count: {total - len(suspicious)}")
    output_lines.append(f"risk_score: {min(100, len(suspicious) * 20)}")
    
    # Add threat breakdown if any
    if threats:
        threat_summary = ', '.join([f"{k}:{v}" for k, v in threats.items()])
        output_lines.append(f"threats: {threat_summary}")
    
    # Add first suspicious URL if any
    if suspicious:
        output_lines.append(f"sample_threat: {suspicious[0]}")
    
    return '\n'.join(output_lines), len(suspicious), total

def main():
    # Get input
    input_text = parse_input()
    
    # Process URLs
    output, suspicious_count, total = process_urls(input_text)
    
    # Determine tags - SIMPLE COMMA-SEPARATED STRING
    tags_list = ["url-scan"]
    
    if total == 0:
        tags_list.append("empty")
    elif suspicious_count == 0:
        tags_list.append("clean")
    elif suspicious_count < total * 0.3:
        tags_list.append("low-risk")
    elif suspicious_count < total * 0.7:
        tags_list.append("medium-risk")
    else:
        tags_list.append("high-risk")
    
    # Add hostname
    try:
        import socket
        tags_list.append(socket.gethostname())
    except:
        pass
    
    # Join tags as simple comma-separated string
    tags = ",".join(tags_list)
    
    # Base64 encode the output
    content = base64.b64encode(output.encode()).decode()
    
    # Output JSON exactly like bash script does
    print(json.dumps({"tags": tags, "content": content}))

if __name__ == "__main__":
    main()