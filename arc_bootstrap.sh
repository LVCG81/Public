#!/bin/bash
# LVCG Edge Node Onboarding - Stage 1 (Public Repo Safe)

echo "Initializing Azure Arc Bootstrap..."

# 1. Mount Volatile RAM for secure execution
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=64M tmpfs /mnt/ramdisk

# 2. Prompt for Identifiers (Visible typing)
read -p "Enter Azure Tenant ID: " TENANT_ID < /dev/tty
read -p "Enter Azure Subscription ID: " SUBSCRIPTION_ID < /dev/tty
read -p "Enter Service Principal Client ID: " SPN_CLIENT_ID < /dev/tty

# 3. Prompt for the Master Key (Hidden typing, never writes to disk)
read -sp "Enter Service Principal Secret: " ARC_SECRET < /dev/tty
echo ""

RESOURCE_GROUP="Drone-Staging-RG"
LOCATION="eastus"

# 4. Fetch the Microsoft Arc Agent directly into RAM
echo "Downloading azcmagent..."
wget -q https://aka.ms/azcmagent -O /mnt/ramdisk/install_linux_azcmagent.sh
# Mute stdout, leave stderr open for fatal errors
sudo bash /mnt/ramdisk/install_linux_azcmagent.sh > /dev/null

# 5. Execute the Zero-Touch Registration
echo "Authenticating to $RESOURCE_GROUP..."
# Mute stdout, leave stderr open for fatal errors
sudo azcmagent connect \
  --service-principal-id "$SPN_CLIENT_ID" \
  --service-principal-secret "$ARC_SECRET" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" > /dev/null

# 6. Burn the Bridge
unset ARC_SECRET
sudo umount -l /mnt/ramdisk
sudo rm -rf /mnt/ramdisk

echo "Bootstrap complete. Identity established."

# 7. Initialize GitOps Pipeline (Ansible)
echo "Installing Ansible and Git..."
# Mute stdout and use -qq for silent package management, leave stderr open
sudo apt-get -qq update > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible git > /dev/null

echo "Executing initial baseline configuration from GitHub..."
# Mute normal playbook success logs, leave stderr open for task failures
sudo ansible-pull -U https://github.com/LVCG81/Public.git baseline.yml > /dev/null

echo "Zero-touch deployment complete. Drone is hardened and reporting to Staging."
