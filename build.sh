#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
swift build -c release

app_dir="${PWD}/dist/EasyAsk.app"
mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
cp .build/release/EasyAsk "${app_dir}/Contents/MacOS/EasyAsk"
cp Resources/Info.plist "${app_dir}/Contents/Info.plist"
cp Resources/mascot-side-peek.png "${app_dir}/Contents/Resources/mascot-side-peek.png"
cp Resources/EasyAsk.icns "${app_dir}/Contents/Resources/EasyAsk.icns"
identity_name='EasyAsk Local Code Signing'
signing_directory="${HOME}/Library/Application Support/EasyAsk/signing"
signing_keychain="${signing_directory}/signing.keychain-db"
password_file="${signing_directory}/keychain-password"
if [[ ! -f "${signing_keychain}" || ! -f "${password_file}" ]]; then
  print -u2 'EasyAsk 的本机签名身份不存在，请先运行 ./setup-signing.sh'
  exit 1
fi
security unlock-keychain -p "$(cat "${password_file}")" "${signing_keychain}"
identity_hash=$(security find-identity -v -p codesigning "${signing_keychain}" | awk -v name="\"${identity_name}\"" 'index($0, name) { print $2; exit }')
if [[ -z "${identity_hash}" ]]; then
  print -u2 'EasyAsk 的本机签名身份不存在，请先运行 ./setup-signing.sh'
  exit 1
fi
codesign --force --sign "${identity_hash}" --keychain "${signing_keychain}" "${app_dir}"
touch "${app_dir}"
echo "Built ${app_dir}"
