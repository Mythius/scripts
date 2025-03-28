#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Prompt for the new username
read -p "Enter the new username: " username

# Create the sshusers group if it doesn't exist
if ! getent group sshusers >/dev/null; then
  groupadd sshusers
fi

# Create a new user and add to sshusers group
useradd -m -G sshusers "$username"

# Check if useradd was successful
if [ $? -ne 0 ]; then
  echo "Failed to create user."
  exit 1
fi

# Prompt for the new user's password
passwd "$username"

# Add the user to the sudo group
usermod -aG sudo "$username"

# Change shell to bash
chsh -s /bin/bash "$username"

# Restart the SSH service
systemctl restart ssh

# Check if the SSH service restarted successfully
if [ $? -eq 0 ]; then
  echo "User $username created and added to sshusers and sudo groups. SSH service restarted successfully."
else
  echo "Failed to restart SSH service."
fi
