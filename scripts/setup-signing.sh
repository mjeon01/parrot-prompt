#!/bin/bash
# One persistent, project-local signing identity. No global trust settings or
# default keychain are changed. Keep .local-signing private and out of git.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
root="$PWD/.local-signing"
keychain="$root/VoicePrompt.keychain-db"
mkdir -p "$root"
chmod 700 "$root"
if [ ! -f "$root/password" ]; then /usr/bin/openssl rand -hex 32 > "$root/password"; fi
if [ ! -f "$root/certificate.pem" ]; then
  cat > "$root/extensions.cnf" <<'EOF'
[code_signing]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF
  /usr/bin/openssl req -new -newkey rsa:2048 -sha256 \
    -keyout "$root/private-key.pem" -passout "file:$root/password" \
    -out "$root/request.csr" -subj '/CN=VoicePrompt Local Development/O=VoicePrompt'
  /usr/bin/openssl x509 -req -in "$root/request.csr" -signkey "$root/private-key.pem" \
    -passin "file:$root/password" -sha256 -days 3650 -extfile "$root/extensions.cnf" \
    -extensions code_signing -out "$root/certificate.pem"
fi
cp "$root/password" "$root/export-password"
/usr/bin/openssl pkcs12 -export -inkey "$root/private-key.pem" -in "$root/certificate.pem" \
  -passin "file:$root/password" -passout "file:$root/export-password" -out "$root/identity.p12"
rm "$root/export-password"
/usr/bin/openssl x509 -in "$root/certificate.pem" -outform DER -out "$root/certificate.der"
identity=$(/usr/bin/openssl x509 -in "$root/certificate.pem" -noout -fingerprint -sha1 | /usr/bin/sed 's/.*=//; s/://g')
printf '%s\n' "$identity" > "$root/identity.txt"
password=$(cat "$root/password")
if [ ! -f "$keychain" ]; then
  /usr/bin/security create-keychain -p "$password" "$keychain"
fi
/usr/bin/security unlock-keychain -p "$password" "$keychain"
if ! /usr/bin/security find-certificate -c 'VoicePrompt Local Development' "$keychain" >/dev/null 2>&1; then
  /usr/bin/security import "$root/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
fi
/usr/bin/security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
printf 'VoicePrompt 서명 준비 완료. ./scripts/build.sh로 빌드하세요.\n'
