#!/bin/bash
# LVCG Edge Node Onboarding - Stage 1 (Public Repo Safe)

# 0. Hardware Prerequisite Check
if [ ! -e /dev/tpm0 ] && [ ! -e /dev/tpmrm0 ]; then
  echo "FATAL ERROR: No Trusted Platform Module (TPM) detected." >&2
  echo "Installation halted: This hardware does not meet minimum security requirements." >&2
  exit 1
fi

# 1. Mount Volatile RAM
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=64M tmpfs /mnt/ramdisk

# 2. Prompt for Identifiers
read -p "Enter Azure Tenant ID: " TENANT_ID < /dev/tty
read -p "Enter Azure Subscription ID: " SUBSCRIPTION_ID < /dev/tty
read -p "Enter Service Principal Client ID: " SPN_CLIENT_ID < /dev/tty

# 3. Prompt for the Master Key
read -sp "Enter Service Principal Secret: " ARC_SECRET < /dev/tty
echo ""

RESOURCE_GROUP="Drone-Staging-RG"
LOCATION="eastus"

# 4. Fetch the Microsoft Arc Agent (100% Silent)
wget -q https://aka.ms/azcmagent -O /mnt/ramdisk/install_linux_azcmagent.sh
if ! sudo -E bash /mnt/ramdisk/install_linux_azcmagent.sh > /dev/null 2>&1; then
  echo "FATAL ERROR: Microsoft Azure Arc installer failed to execute." >&2
  exit 1
fi

# 5. Execute the Zero-Touch Registration (100% Silent)
if ! sudo azcmagent connect \
  --service-principal-id "$SPN_CLIENT_ID" \
  --service-principal-secret "$ARC_SECRET" \
  --tenant-id "$TENANT_ID" \
  --subscription-id "$SUBSCRIPTION_ID" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" > /mnt/ramdisk/arc_connect_error.log 2>&1; then
  
  echo "FATAL ERROR: Azure Arc Connection Failed! Check credentials." >&2
  exit 1
fi

# 6. Burn the Bridge
unset ARC_SECRET
sudo umount -l /mnt/ramdisk
sudo rm -rf /mnt/ramdisk 2>/dev/null

# 7. Initialize GitOps Pipeline (100% Silent)
# Environment variables forcefully suppress 'needrestart' and interactive prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if ! sudo -E apt-get -q=2 update >/dev/null 2>&1 || ! sudo -E apt-get -q=2 install -y ansible git >/dev/null 2>&1; then
  echo "FATAL ERROR: Failed to install Ansible and Git dependencies." >&2
  exit 1
fi

# 8. Execute Ansible Pull (Logged to disk for debugging)
if ! sudo ansible-pull -U https://github.com/LVCG81/Public.git baseline.yml > /var/log/ansible-bootstrap.log 2>&1; then
  echo "FATAL ERROR: Ansible baseline configuration failed." >&2
  exit 1
fi

# NEW: If we made it this far, the deployment succeeded. Burn the local log.
sudo rm -f /var/log/ansible-bootstrap.log

echo "Zero-touch deployment complete. Drone is hardened and reporting to Staging."
