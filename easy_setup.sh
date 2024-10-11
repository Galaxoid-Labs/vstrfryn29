#!/bin/bash

# Ask for the domain (this is required)
while true; do
    read -p "Please enter your domain without protocol. Example: relay29.domain.com (required): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        break
    else
        echo "Error: Domain is required!"
    fi
done

# Ask for the other optional inputs
read -p "Enter a name for the relay (optional): " RELAY_NAME
read -p "Enter a description for the relay (optional): " DESCRIPTION
read -p "Enter the hex pubkey for administration (optional): " PUBKEY
read -p "Enter the contact information (optional): " CONTACT
read -p "Enter the URL for the relay's icon (optional): " ICON

# Ask for the private key hex (this is required)
while true; do
    read -p "Please enter the private key hex to use for the relay (required): " PRIVATE_KEY_HEX
    if [[ -n "$PRIVATE_KEY_HEX" ]]; then
        break
    else
        echo "Error: Private key hex is required!"
    fi
done

# Download zip file (update with the actual URL)
ZIP_URL="https://github.com/Galaxoid-Labs/vstrfryn29/releases/download/0.1.0-alpha/relay.zip"
DOWNLOAD_PATH="/tmp/relay.zip"

echo "Downloading zip file from $ZIP_URL..."
curl -L -o $DOWNLOAD_PATH $ZIP_URL

# Unzip to specific location (change to your desired location)
UNZIP_PATH="$HOME"
echo "Unzipping to $UNZIP_PATH..."
unzip $DOWNLOAD_PATH -d $UNZIP_PATH

# Modify strfry.conf (assume it's in the unzipped folder)
STRFRY_CONF="$UNZIP_PATH/relay/strfry.conf"
if [ -f $STRFRY_CONF ]; then
    # Replace the line db = "" with the home directory and /relay/strfry-db/
    HOME_DB_PATH="$HOME/relay/strfry-db/"
    PLUGIN_PATH="$HOME/relay/plugins/vstrfryn29"
    
    echo "Modifying strfry.conf with the following information:"
    echo "Domain: $DOMAIN"
    echo "Name: $RELAY_NAME"
    echo "Description: $DESCRIPTION"
    echo "Pubkey: $PUBKEY"
    echo "Contact: $CONTACT"
    echo "Icon URL: $ICON"
    
    # Perform replacements in strfry.conf
    sed -i "s|db = \"\"|db = \"$HOME_DB_PATH\"|" $STRFRY_CONF
    sed -i "s|plugin = \"\"|plugin = \"$PLUGIN_PATH\"|" $STRFRY_CONF
    sed -i "s|name = \"\"|name = \"$RELAY_NAME\"|" $STRFRY_CONF
    sed -i "s|description = \"\"|description = \"$DESCRIPTION\"|" $STRFRY_CONF
    sed -i "s|pubkey = \"\"|pubkey = \"$PUBKEY\"|" $STRFRY_CONF
    sed -i "s|contact = \"\"|contact = \"$CONTACT\"|" $STRFRY_CONF
    sed -i "s|icon = \"\"|icon = \"$ICON\"|" $STRFRY_CONF
else
    echo "strfry.conf not found!"
    exit 1
fi

# Modify vstrfryn29.toml with the private key hex
VSTRFRY_TOML="$UNZIP_PATH/relay/plugins/vstrfryn29.toml"
if [ -f $VSTRFRY_TOML ]; then
    echo "Modifying vstrfryn29.toml with the private key hex..."
    sed -i "s|pk_hex = \"\"|pk_hex = \"$PRIVATE_KEY_HEX\"|" $VSTRFRY_TOML
else
    echo "vstrfryn29.toml not found!"
    exit 1
fi

# Move modified strfry.conf to /etc
echo "Moving strfry.conf to /etc/strfry.conf..."
sudo mv $STRFRY_CONF /etc/strfry.conf

# Add path to .bashrc
BASHRC_PATH="$HOME/.bashrc"
NEW_PATH="export PATH=\$PATH:$HOME/relay"
if ! grep -Fxq "$NEW_PATH" $BASHRC_PATH; then
    echo "Adding new path to .bashrc..."
    echo "$NEW_PATH" >> $BASHRC_PATH
else
    echo "Path already exists in .bashrc!"
fi

# Reload .bashrc
echo "Reloading .bashrc..."
source $BASHRC_PATH

# Remove the downloaded zip file
echo "Removing the downloaded zip file..."
rm $DOWNLOAD_PATH

# Install Caddy
echo "Installing Caddy..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# Setup Caddyfile
CADDYFILE_PATH="/etc/caddy/Caddyfile"

echo "$DOMAIN
reverse_proxy :7777" | sudo tee $CADDYFILE_PATH

# Restart Caddy to apply the changes
echo "Restarting Caddy..."
sudo systemctl restart caddy

echo "Script execution completed!"
echo "Now simply run strfry relay to start the relay. You'll probably want to use something like screen or setup a service to run this in the background"
