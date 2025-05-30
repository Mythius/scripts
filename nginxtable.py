#!/usr/bin/env python3

import os
import re
from urllib.parse import urlparse

NGINX_DIR = "/etc/nginx/sites-enabled"

def extract_server_blocks(config_text):
    """Extract individual server blocks from a full nginx config file."""
    blocks = []
    stack = []
    start_idx = None

    for i, line in enumerate(config_text):
        if "server {" in line:
            if not stack:
                start_idx = i
            stack.append("{")
        elif "{" in line:
            stack.append("{")
        elif "}" in line:
            if stack:
                stack.pop()
                if not stack and start_idx is not None:
                    blocks.append(config_text[start_idx:i+1])
                    start_idx = None
    return blocks

def parse_server_block(block_lines):
    """Parse a single server block for server_name and proxy_pass."""
    server_name = None
    proxy_passes = []

    for line in block_lines:
        line = line.strip()
        if not server_name and line.startswith("server_name"):
            match = re.match(r"server_name\s+([^;]+);", line)
            if match:
                server_name = match.group(1).strip()
        elif line.startswith("proxy_pass"):
            match = re.match(r"proxy_pass\s+([^;]+);", line)
            if match:
                proxy_passes.append(match.group(1).strip())

    if not proxy_passes:
        return []  # Ignore blocks without reverse proxying

    return [(server_name or "", proxy) for proxy in proxy_passes]

def extract_port(url):
    """Extract port from proxy_pass URL; fallback to default ports."""
    try:
        parsed = urlparse(url)
        if parsed.port:
            return parsed.port
        return 80 if parsed.scheme == "http" else 443
    except Exception:
        return float('inf')  # fallback for malformed URLs

def process_file(path):
    with open(path, 'r') as f:
        lines = f.readlines()
        blocks = extract_server_blocks(lines)
        entries = []
        for block in blocks:
            entries.extend(parse_server_block(block))
        return entries

# Main
def main():
    try:
        files = [os.path.join(NGINX_DIR, f) for f in os.listdir(NGINX_DIR)
                 if os.path.isfile(os.path.join(NGINX_DIR, f))]
        if not files:
            raise FileNotFoundError("No config files found.")
    except Exception as e:
        print(f"Error: {e}")
        return

    all_entries = []
    for file_path in files:
        all_entries.extend(process_file(file_path))

    # Sort by extracted port number
    all_entries.sort(key=lambda entry: extract_port(entry[1]))

    print("name\tforward_location")
    for name, location in all_entries:
        print(f"{name}\t{location}")

if __name__ == "__main__":
    main()
