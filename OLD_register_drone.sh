#!/bin/bash
# LVCG Unified Bootstrap Agent

echo "Initializing LVCG Drone Bootstrap..."

# 0. Install Prerequisites (Silent Install)
sudo apt-get update -qq
sudo apt-get install -y tpm2-tools jq curl -qq

# 1. Generate Local SSH Key if missing
if [ ! -f /home/administrator/.ssh/id_ed25519.pub ]; then
    echo "Generating missing SSH key for administrator..."
    sudo -u administrator ssh-keygen -t ed25519 -f /home/administrator/.ssh/id_ed25519 -N "" -q
fi

# 2. Setup Phase 1: Volatile Environment
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=256M tmpfs /mnt/ramdisk

# 3. Extract Hardware Identity & Prompt for Provisioning Key (Forcing TTY for the prompt)
UUID=$(sudo cat /sys/class/dmi/id/product_uuid)
read -sp "Enter the 64-character LVCG Provisioning OTP: " OTP < /dev/tty
echo "" # Clean newline
PUB_KEY=$(cat /home/administrator/.ssh/id_ed25519.pub)
TIMESTAMP=$(date --utc +%s)

# 4. Construct Compliant Payload
PAYLOAD=$(jq -n \
  --arg uuid "$UUID" \
  --arg otp "$OTP" \
  --arg pub_key "$PUB_KEY" \
  --argjson timestamp "$TIMESTAMP" \
  '{vm_uuid: $uuid, otp: $otp, public_key: $pub_key, timestamp: $timestamp}')

# 5. Phase 2: Layer 7 Sign-Then-Send (TPM Enforcement)
# Create a primary key that allows signing
tpm2_createprimary -C o -c primary.ctx > /dev/null 2>&1
tpm2_create -C primary.ctx -u key.pub -r key.priv -c signing_key.ctx -g sha256 -G rsa2048 -a "sign|fixedtpm|fixedparent" > /dev/null 2>&1
tpm2_load -C primary.ctx -u key.pub -r key.priv -c load.ctx > /dev/null 2>&1

# Sign the payload
echo -n "$PAYLOAD" > payload.bin
tpm2_sign -c load.ctx -g sha256 -o signature.dat payload.bin
SIG_BASE64=$(base64 -w 0 signature.dat)

# Changed -s to -o for TPM2-Tools v5+ compatibility
echo -n "$PAYLOAD" | tpm2_sign -c primary.ctx -g sha256 -o signature.dat -f plain
SIG_BASE64=$(base64 -w 0 signature.dat)

# 6. Handshake & Phase 3 Hand-off
echo "Registering with LVCG Orchestrator..."
RESPONSE=$(curl -s -X POST "https://lvcg-enrollment-api.graycliff-a6e72cc9.northcentralus.azurecontainerapps.io/api/v1/enroll" \
  -H "Content-Type: application/json" \
  -H "X-LVCG-Signature: $SIG_BASE64" \
  -d "$PAYLOAD")

# 7. Parse and Execute Phase 3 Hardening Script
HARDENING_SCRIPT=$(echo "$RESPONSE" | jq -r '.hardening_script // empty')

if [ -n "$HARDENING_SCRIPT" ] && [ "$HARDENING_SCRIPT" != "null" ]; then
    echo "Payload received. Executing lockdown..."
    echo "$HARDENING_SCRIPT" > /mnt/ramdisk/harden_and_verify.sh
    chmod +x /mnt/ramdisk/harden_and_verify.sh
    
    sudo /mnt/ramdisk/harden_and_verify.sh
else
    echo "Error: No hardening script received. Registration failed."
    echo "API Response: $RESPONSE"
    exit 1
fi
