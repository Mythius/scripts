#!/bin/bash

# Function to show usage instructions
usage() {
    echo "Usage: $0 <subdomain> <port>"
    echo "  subdomain - The subdomain for the Nginx configuration (e.g., example.domain.com)"
    echo "  port      - The port number to proxy traffic to (e.g., 3000)"
    exit 1
}

# Ensure exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Error: Invalid number of arguments!"
    usage
fi

subdomain="$1"
port="$2"

# Validate subdomain (basic check for a valid domain name format)
if [[ ! "$subdomain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Error: Invalid subdomain '$subdomain'. Only letters, numbers, dots, and dashes are allowed."
    exit 1
fi

# Validate port (must be a number between 1 and 65535)
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "Error: Invalid port '$port'. It must be a number between 1 and 65535."
    exit 1
fi

# Ensure Nginx configuration directory exists
nginx_config_dir="/etc/nginx/sites-enabled"
if [ ! -d "$nginx_config_dir" ]; then
    echo "Error: Nginx configuration directory '$nginx_config_dir' does not exist."
    echo "Make sure Nginx is installed."
    exit 1
fi

# Define the configuration file path
config_file="$nginx_config_dir/$subdomain"

# Prevent overwriting an existing configuration
if [ -f "$config_file" ]; then
    echo "Warning: Configuration for '$subdomain' already exists."
    read -p "Do you want to overwrite it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborting."
        exit 1
    fi
fi

# Create Nginx configuration
cat <<EOF > "$config_file"
server {
    listen 80;
    server_name $subdomain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Host \$host;
    }
}
EOF

echo "Nginx configuration for '$subdomain' created successfully at $config_file."

# Test Nginx configuration before restarting
nginx -t
if [ $? -ne 0 ]; then
    echo "Error: Nginx configuration test failed! Please check the logs."
    exit 1
fi

# Restart Nginx
systemctl restart nginx
echo "Nginx restarted successfully."

# Install HTTPS certificate using Certbot
echo "Installing SSL certificate for $subdomain..."
certbot --nginx -d "$subdomain" --redirect --non-interactive --agree-tos --email admin@$subdomain

# Verify if SSL was installed successfully
if [ $? -eq 0 ]; then
    echo "SSL certificate successfully installed for $subdomain."
else
    echo "Warning: Certbot may have failed. Check logs and manually install SSL if needed."
fi
