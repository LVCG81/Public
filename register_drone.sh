#!/bin/bash
# LVCG Unified Bootstrap Agent

# 1. Setup Phase 1: Volatile Environment
sudo mkdir -p /mnt/ramdisk
sudo mount -t tmpfs -o size=256M tmpfs /mnt/ramdisk

# 2. Extract Hardware Identity & Prompt for Provisioning Key
UUID=$(sudo cat /sys/class/dmi/id/product_uuid)
read -sp "Enter the 64-character LVCG Provisioning OTP: " OTP
echo "" # Clean newline after silent prompt
PUB_KEY=$(cat /home/administrator/.ssh/id_ed25519.pub)
TIMESTAMP=$(date --utc +%s)

# 3. Construct Compliant Payload
PAYLOAD=$(printf '{"vm_uuid": "%s", "otp": "%s", "public_key": "%s", "timestamp": %s}' "$UUID" "$OTP" "$PUB_KEY" "$TIMESTAMP")

# 4. Phase 2: Layer 7 Sign-Then-Send (TPM Enforcement)
echo -n "$PAYLOAD" | tpm2_sign -c primary.ctx -g sha256 -s signature.dat -f plain -
SIG_BASE64=$(base64 -w 0 signature.dat)

# 5. Handshake & Phase 3 Hand-off
echo "Registering with LVCG Orchestrator..."
# Note: Endpoint shifted to /enroll to match the API logic
RESPONSE=$(curl -s -X POST "https://lvcg-enrollment-api.graycliff-a6e72cc9.northcentralus.azurecontainerapps.io/api/v1/enroll" \
  -H "Content-Type: application/json" \
  -H "X-LVCG-Signature: $SIG_BASE64" \
  -d "$PAYLOAD")

# 6. Parse and Execute Phase 3 Hardening Script
# Requires 'jq' installed on the base image
HARDENING_SCRIPT=$(echo "$RESPONSE" | jq -r '.hardening_script // empty')

if [ -n "$HARDENING_SCRIPT" ] && [ "$HARDENING_SCRIPT" != "null" ]; then
    echo "$HARDENING_SCRIPT" > /mnt/ramdisk/harden_and_verify.sh
    chmod +x /mnt/ramdisk/harden_and_verify.sh
    
    # Execute as sudo to ensure lockdown commands succeed
    sudo /mnt/ramdisk/harden_and_verify.sh
else
    echo "Error: No hardening script received. Registration failed."
    echo "API Response: $RESPONSE"
    exit 1
fi
