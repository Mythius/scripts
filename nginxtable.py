#!/usr/bin/env python3

import os
import re
from urllib.parse import urlparse
import subprocess
import sys
import json

NGINX_DIR = "/etc/nginx/sites-enabled"

def extract_server_blocks(config_text):
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
        return []
    return [(server_name or "", proxy) for proxy in proxy_passes]

def extract_port(url):
    try:
        parsed = urlparse(url)
        if parsed.port:
            return parsed.port
        return 80 if parsed.scheme == "http" else 443
    except Exception:
        return None

def get_process_info_for_port(port):
    try:
        output = subprocess.check_output(
            ["lsof", "-i", f"TCP:{port}", "-sTCP:LISTEN", "-P", "-n"],
            stderr=subprocess.DEVNULL
        ).decode()
        lines = output.strip().split('\n')
        if len(lines) < 2:
            return ('unknown', 'unknown')
        # Parse first match (skip header)
        parts = lines[1].split()
        if len(parts) >= 2:
            process_name = parts[0].lower()
            pid = parts[1]
            cwd_path = f"/proc/{pid}/cwd"
            try:
                cwd = os.readlink(cwd_path)
            except Exception:
                cwd = 'unknown'
            # Normalize name
            if 'node' in process_name:
                process_type = 'node'
            elif 'python' in process_name:
                process_type = 'python'
            elif 'apache' in process_name or 'httpd' in process_name:
                process_type = 'apache'
            else:
                process_type = process_name
            return (process_type, cwd)
    except subprocess.CalledProcessError:
        pass
    return ('none', 'none')


def process_file(path):
    with open(path, 'r') as f:
        lines = f.readlines()
        blocks = extract_server_blocks(lines)
        entries = []
        for block in blocks:
            entries.extend(parse_server_block(block))
        return entries

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

    enriched = []
    for name, location in all_entries:
        port = extract_port(location)
        if port:
            process_type, cwd = get_process_info_for_port(port)
        else:
            process_type, cwd = 'none', 'none'
        enriched.append((name, location, port, process_type, cwd))

    # Sort by port
    enriched.sort(key=lambda x: x[2] if x[2] is not None else 99999)

    # Calculate column widths
    name_width = max(len("name"), *(len(str(row[0])) for row in enriched))
    location_width = max(len("forward_location"), *(len(str(row[1])) for row in enriched))
    process_type_width = max(len("process_type"), *(len(str(row[3])) for row in enriched))
    cwd_width = max(len("cwd"), *(len(str(row[4])) for row in enriched))

    header_fmt = f"{{:<{name_width}}}  {{:<{location_width}}}  {{:<{process_type_width}}}  {{:<{cwd_width}}}"
    row_fmt = header_fmt

    if "--json" not in sys.argv:
        print(header_fmt.format("name", "forward_location", "process_type", "cwd"))
        print("-" * (name_width + location_width + process_type_width + cwd_width + 6))


    for name, location, _, process_type, cwd in enriched:
        if "--json" in sys.argv:
            # Output all enriched rows as a JSON array of dicts
            json_rows = [
            {
                "name": name,
                "forward_location": location,
                "process_type": process_type,
                "cwd": cwd
            }
            for name, location, _, process_type, cwd in enriched
            ]
            print(json.dumps(json_rows, indent=2))
            break
        else:
            print(row_fmt.format(name, location, process_type, cwd))

if __name__ == "__main__":
    main()
