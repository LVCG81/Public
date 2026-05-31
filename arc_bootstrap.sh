#!/bin/bash
# LVCG Edge Node Onboarding - Stage 1 (Public Repo Safe)

# 0. Hardware Prerequisite Check: Ensure TPM is present
if [ ! -e /dev/tpm0 ] && [ ! -e /dev/tpmrm0 ]; then
  echo "FATAL ERROR: No Trusted Platform Module (TPM) detected." >&2
  echo "Installation halted: This hardware does not meet minimum security requirements." >&2
  exit 1
fi

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
wget -q https://aka.ms/azcmagent -O /mnt/ramdisk/install_linux_azcmagent.sh
# Mute stdout, leave stderr open for fatal errors
sudo bash /mnt/ramdisk/install_linux_azcmagent.sh > /dev/null

# 5. Execute the Zero-Touch Registration
# (Removed the echo statement here)
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
# Appended 2>/dev/null to swallow the 'Device or resource busy' error
sudo rm -rf /mnt/ramdisk 2>/dev/null

# (Removed the Bootstrap complete echo here)

# 7. Initialize GitOps Pipeline (Ansible)
# (Removed the Installing Ansible echo here)
sudo apt-get -qq update > /dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ansible git > /dev/null

# (Removed the Executing initial baseline echo here)
sudo ansible-pull -U https://github.com/LVCG81/Public.git baseline.yml > /dev/null

echo "Zero-touch deployment complete. Drone is hardened and reporting to Staging."
