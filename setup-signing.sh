#!/bin/zsh
set -euo pipefail

identity_name='EasyAsk Local Code Signing'
login_keychain="${HOME}/Library/Keychains/login.keychain-db"
signing_directory="${HOME}/Library/Application Support/EasyAsk/signing"
signing_keychain="${signing_directory}/signing.keychain-db"
password_file="${signing_directory}/keychain-password"
mkdir -p "${signing_directory}"
chmod 700 "${signing_directory}"
if [[ -f "${signing_keychain}" && -f "${password_file}" ]]; then
  security unlock-keychain -p "$(cat "${password_file}")" "${signing_keychain}"
  if security find-identity -v -p codesigning "${signing_keychain}" | rg -F "\"${identity_name}\"" >/dev/null; then
    security list-keychains -d user -s "${login_keychain}" "${signing_keychain}"
    echo 'EasyAsk 本机签名身份已存在。'
    exit 0
  fi
fi

umask 077
temporary_directory=$(mktemp -d /tmp/EasyAskSigning.XXXXXX)
cleanup() {
  swift -e 'import Foundation; try? FileManager.default.removeItem(atPath: CommandLine.arguments[1])' "${temporary_directory}" >/dev/null 2>&1
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=${identity_name}" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=digitalSignature' \
  -addext 'extendedKeyUsage=codeSigning' \
  -keyout "${temporary_directory}/identity.key" \
  -out "${temporary_directory}/identity.crt" >/dev/null 2>&1

archive_password=$(openssl rand -hex 24)
keychain_password=$(openssl rand -hex 24)
print -rn -- "${keychain_password}" > "${password_file}"
chmod 600 "${password_file}"
security create-keychain -p "${keychain_password}" "${signing_keychain}"
security unlock-keychain -p "${keychain_password}" "${signing_keychain}"
openssl pkcs12 -legacy -export \
  -inkey "${temporary_directory}/identity.key" \
  -in "${temporary_directory}/identity.crt" \
  -out "${temporary_directory}/identity.p12" \
  -passout "pass:${archive_password}" >/dev/null 2>&1

security import "${temporary_directory}/identity.p12" \
  -k "${signing_keychain}" -P "${archive_password}" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign \
  -k "${signing_keychain}" "${temporary_directory}/identity.crt"
security list-keychains -d user -s "${login_keychain}" "${signing_keychain}"

if ! security find-identity -v -p codesigning "${signing_keychain}" | rg -F "\"${identity_name}\"" >/dev/null; then
  print -u2 '签名身份创建失败。'
  exit 1
fi
echo 'EasyAsk 本机签名身份已创建；后续构建会复用该身份。'
