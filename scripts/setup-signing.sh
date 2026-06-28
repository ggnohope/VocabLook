#!/usr/bin/env bash
# Create a stable self-signed code-signing identity ("VocabLook Dev") in the login keychain.
#
# Why: macOS TCC (Accessibility / Input Monitoring) grants are tied to the app's code signature.
# Ad-hoc signing changes the signature hash on every build, so each rebuild would require
# re-granting permissions. Signing with a stable self-signed certificate keeps the Designated
# Requirement constant across rebuilds, so you grant the two permissions exactly once.
#
# Run this ONCE. Afterwards bundle-app.sh automatically signs with this identity.
set -euo pipefail

NAME="VocabLook Dev"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "Signing identity '$NAME' already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -nodes -config "$WORK/cfg" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass:vl -name "$NAME" >/dev/null 2>&1

security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P vl -A -T /usr/bin/codesign

echo "Created signing identity '$NAME'. You can now run ./scripts/run.sh"
