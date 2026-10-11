#!/bin/bash
set -euo pipefail
identity='Snap Local Distribution'
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    echo 'Existing Snap signing certificate found; preserving it.'
    exit 0
fi
umask 077
temporary="$(mktemp -d /tmp/snap-signing.XXXXXX)"
trap 'rm -rf "$temporary"' EXIT
cat > "$temporary/certificate.cnf" <<'EOF'
[req]
distinguished_name = identity
x509_extensions = signing
prompt = no
[identity]
CN = Snap Local Distribution
[signing]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
openssl req -new -newkey rsa:3072 -nodes -x509 -sha256 -days 3650 \
    -config "$temporary/certificate.cnf" \
    -keyout "$temporary/key.pem" -out "$temporary/certificate.pem" 2>/dev/null
openssl rand -base64 32 > "$temporary/password"
openssl pkcs12 -export -name "$identity" -inkey "$temporary/key.pem" \
    -in "$temporary/certificate.pem" -out "$temporary/identity.p12" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "file:$temporary/password"
keychain="$HOME/Library/Keychains/login.keychain-db"
security import "$temporary/identity.p12" -k "$keychain" \
    -P "$(cat "$temporary/password")" -T /usr/bin/codesign
# Trust only this user's code-signing policy, not SSL or the system trust store.
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$temporary/certificate.pem"
echo 'Snap Local Distribution identity created in the login Keychain.'
echo 'Preserve this identity and private key for future releases; do not distribute the key.'
