#!/usr/bin/env bash
# 로컬 코드 서명용 self-signed 인증서를 login keychain에 만든다 (멱등).
#
# **왜 필요한가.** ad-hoc 서명(`codesign -s -`)은 안정적인 정체성이 없어, 앱을 재빌드할 때마다
# macOS TCC(문서·데스크톱 폴더 접근 권한)가 "처음 보는 앱"으로 취급한다 — 사용자가 "허용"을 눌러도
# 재설치하면 권한이 리셋돼 git 폴링·파일 감시 때마다 권한 프롬프트가 반복해서 뜬다.
# self-signed 인증서로 서명하면 코드 서명의 designated requirement가 **인증서 leaf에 고정**되어,
# 같은 인증서로 재서명하는 한 바이너리가 바뀌어도 정체성이 유지된다 → 권한을 한 번만 주면 된다.
#
# 이건 **로컬 개발 전용**이다 — 배포·공증엔 유료 Apple Developer 계정의 Developer ID가 필요하다.
# 무료·계정 불필요. 다른 머신에서도 이 스크립트를 한 번 실행하면 같은 이름의 인증서가 생긴다.
set -euo pipefail

CERT_NAME="muxa Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "이미 있음: '$CERT_NAME' — build-app.sh가 자동으로 이 인증서로 서명한다."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# code signing 목적(extendedKeyUsage=codeSigning)을 가진 self-signed X.509. LibreSSL(macOS 기본) 호환.
cat >"$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# **macOS 기본 openssl(LibreSSL)을 명시적으로 쓴다.** PATH의 openssl이 Homebrew OpenSSL 3.x면
# pkcs12를 SHA256 MAC 등 최신 알고리즘으로 묶어, macOS의 SecKeychainItemImport가
# "MAC verification failed"로 거부한다. LibreSSL은 레거시(SHA1 MAC·3DES)를 기본으로 써서 호환된다.
SSL=/usr/bin/openssl

"$SSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf" >/dev/null 2>&1

# 임시 비번은 keychain import 순간만 쓰이고 버려진다(인증서·키는 keychain이 보관).
"$SSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$CERT_NAME" -out "$TMP/id.p12" -passout pass:muxa-local >/dev/null 2>&1

# -A: codesign이 keychain 암호 프롬프트 없이 이 키를 쓰게 한다(로컬 개발 인증서라 허용 범위를 연다).
security import "$TMP/id.p12" -k "$KEYCHAIN" -P muxa-local -A >/dev/null

echo "만들었다: '$CERT_NAME' (10년 유효)."
echo "이제 build-app.sh가 자동으로 이 인증서로 서명한다 — 재빌드해도 TCC 권한이 유지된다."
