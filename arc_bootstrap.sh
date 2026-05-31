#!/bin/bash
# LVCG Edge Node Onboarding - Stage 1 (Public Repo Safe)

# Global Silence Variables (Kills Ubuntu "Scanning processes" and package noise)
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_SUSPEND=1

echo "Initializing Azure Arc Bootstrap..."

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

# Mute BOTH stdout and stderr to permanently hide Microsoft's 3 internal 'apt' warnings
sudo -E bash /mnt/ramdisk/install_linux_azcmagent.sh > /dev/null 2>&1

# 5. Execute the Zero-Touch Registration (Leaves stderr open for fatal connection errors)
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
# Adding 2>/dev/null hides the harmless 'device busy' warning
sudo rm -rf /mnt/ramdisk 2>/dev/null

# 7. Initialize GitOps Pipeline (Ansible)
# The -E flag ensures the global silence variables pass through the sudo boundary
sudo -E apt-get -qq update > /dev/null
sudo -E apt-get install -y -qq ansible git > /dev/null

# Execute Ansible Pull (Leaves stderr open to catch playbook failures)
sudo ansible-pull -U https://github.com/LVCG81/Public.git baseline.yml > /dev/null

echo "Zero-touch deployment complete. Drone is hardened and reporting to Staging."
