#!/bin/bash

# Usage message function
usage() {
    echo "Usage: $0 <service_name> <script_path>"
    echo "  service_name  - Name of the systemd service to create"
    echo "  script_path   - Path to the shell script to execute"
    exit 1
}

# Ensure exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments!"
    usage
fi

name="$1"
shfile="$2"
sn="$name.service"
path="/etc/systemd/system/$sn"

# Validate service name (alphanumeric + underscores allowed)
if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Service name '$name' contains invalid characters."
    echo "Use only letters, numbers, dashes, and underscores."
    exit 1
fi

# Check if the script file exists and is executable
if [ ! -f "$shfile" ]; then
    echo "Error: Script file '$shfile' does not exist."
    exit 1
fi

# Check if service already exists
if [ -f "$path" ]; then
    echo "Warning: Service '$name' already exists at $path."
    read -p "Do you want to overwrite it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# Create systemd service file
echo "[Unit]" > "$path"
echo "Description=Server for $name" >> "$path"
echo "[Service]" >> "$path"
echo "User=root" >> "$path"
echo "ExecStart=/bin/bash $shfile" >> "$path"
echo "Restart=on-failure" >> "$path"
echo "RestartSec=1s" >> "$path"
echo "[Install]" >> "$path"
echo "WantedBy=multi-user.target" >> "$path"

# Reload systemd, enable, and start the service
systemctl daemon-reload
systemctl enable "$sn"
systemctl start "$sn"

echo "Service '$sn' created and started successfully."
