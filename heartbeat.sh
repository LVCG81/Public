#!/bin/bash
# LVCG Heartbeat - TPM Signed
API_ENDPOINT="https://lvcg-enrollment-api.graycliff-a6e72cc9.northcentralus.azurecontainerapps.io/api/v1/policies/pull"
UUID=$(cat /etc/machine-id | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')
TIMESTAMP=$(date +%s)
PAYLOAD="{\"vm_uuid\": \"$UUID\", \"timestamp\": $TIMESTAMP}"
SIG_FILE="/tmp/payload.sig"
HASH_FILE="/tmp/payload.sha256"

echo -n "$PAYLOAD" | sha256sum | awk '{print $1}' > "$HASH_FILE"
sudo tpm2_sign -c 0x81010001 -g sha256 -o "$SIG_FILE" "$HASH_FILE"

sudo curl -s -X POST "$API_ENDPOINT" \
  -H "Content-Type: application/json" \
  -H "X-LVCG-Signature: $(base64 -w 0 $SIG_FILE)" \
  -d "$PAYLOAD"
