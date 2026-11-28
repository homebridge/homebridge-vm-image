#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the script under test as it is
# The nginx config of the image and the self-signed certificate.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

SITE="$REPO/assets/03-nginx/files/homebridge.local"

# check_with_nginx <text> <file>: nginx itself must accept the file, with no warning
check_with_nginx() {
  local answer
  answer="$(nginx_accepts "$2")"
  case $? in
    0) ok "$1" ;;
    2) echo "  skip  $1 (nginx is not installed here)" ;;
    *) fail "$1" "$answer" ;;
  esac
}

check_with_nginx "nginx accepts the config of the image, with no warning" "$SITE"
has "the image config turns HTTP/2 on the current way" "$SITE" "http2 on;"
isnt "the image config does not use the old 'listen ... http2' form" grep -qE 'listen .*http2' "$SITE"
has "the image config sends the X-Forwarded-For header" "$SITE" 'X-Forwarded-For $proxy_add_x_forwarded_for;'
hasnt "the misspelled header name is gone" "$SITE" 'X-Forward-For'

PAGE="$REPO/assets/03-nginx/files/custom_502.html"
hasnt "the 'Homebridge is not running' page does not link to the Raspberry Pi wiki" "$PAGE" "homebridge-raspbian-image"
has "it links to the VM wiki page" "$PAGE" "https://github.com/homebridge/homebridge/wiki/Install-Homebridge-on-Virtual-Machine"

# ---- the self-signed certificate (uses the real openssl)
CERT_SCRIPT="$REPO/assets/03-nginx/files/nginx-homebridge-self-signed-cert"
C="$W/cert"
SSL="$C/etc/nginx/ssl"
cert_script() {
  sed -E "s#(^|[[:space:]=\"])/etc/nginx/#\1$C/etc/nginx/#g" "$CERT_SCRIPT" > "$W/cert-script"
  ( PATH="$W/bin:$PATH" bash "$W/cert-script" ) > "$W/cert.log" 2>&1
}
fresh_cert() { rm -rf "$C" && mkdir -p "$C/etc/nginx/sites-available" && touch "$C/etc/nginx/sites-available/homebridge.local"; }
names() { openssl x509 -noout -ext subjectAltName -in "$SSL/homebridge.local.crt" 2> /dev/null | tail -n 1 | tr -d ' '; }
sum() { sha256sum "$SSL/homebridge.local.crt" | cut -d' ' -f1; }
# old_cert <subject> <days>: a self-signed certificate as made before, valid for <days> days
old_cert() {
  mkdir -p "$SSL"
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$2" -subj "$1" \
    -keyout "$SSL/homebridge.local.key" -out "$SSL/homebridge.local.crt" 2> /dev/null
}

fake hostname 'echo my-vm'

fresh_cert
cert_script
same "makes a certificate when there is none" "$?" "0"
same "the certificate names localhost, homebridge-vm.local and the VM's own name" "$(names)" "DNS:localhost,DNS:homebridge-vm.local,IPAddress:127.0.0.1,DNS:my-vm,DNS:my-vm.local"
same "only root can read the key" "$(stat -c '%a' "$SSL/homebridge.local.key")" "600"
is "the certificate is valid for more than two years" openssl x509 -checkend $((800 * 86400)) -noout -in "$SSL/homebridge.local.crt"
isnt "and for less than 826 days (the longest Apple devices accept)" openssl x509 -checkend $((826 * 86400)) -noout -in "$SSL/homebridge.local.crt"
is "the key belongs to the certificate" bash -c "[ \"\$(openssl x509 -noout -pubkey -in '$SSL/homebridge.local.crt' | sha256sum)\" = \"\$(openssl pkey -pubout -in '$SSL/homebridge.local.key' | sha256sum)\" ]"

before="$(sum)"
cert_script
same "a certificate that is still valid is left alone" "$(sum)" "$before"

fresh_cert && old_cert "/CN=localhost" 10 && before="$(sum)"
cert_script
isnt "a certificate made by an older image that expires soon is replaced" test "$(sum)" = "$before"
is "the new one is valid for a long time again" openssl x509 -checkend $((800 * 86400)) -noout -in "$SSL/homebridge.local.crt"

fresh_cert && old_cert "/O=Homebridge VM Image/CN=homebridge-vm.local" 10 && before="$(sum)"
cert_script
isnt "a certificate made by this image that expires soon is replaced" test "$(sum)" = "$before"

fresh_cert && old_cert "/CN=my-own-name.example.com" 10 && before="$(sum)"
cert_script
same "a certificate the user put there is never replaced, even when it expires soon" "$(sum)" "$before"

fresh_cert && mkdir -p "$SSL" && echo "not a certificate" > "$SSL/homebridge.local.crt" && echo "key" > "$SSL/homebridge.local.key" && before="$(sum)"
cert_script
same "a file that is not a certificate is not replaced" "$(sum)" "$before"

fresh_cert
fake hostname 'echo homebridge-vm'
cert_script
same "the name the image is built with is not listed twice" "$(names)" "DNS:localhost,DNS:homebridge-vm.local,IPAddress:127.0.0.1"

fresh_cert
fake hostname 'echo "bad name; x"'
cert_script
same "a host name with other characters is left out" "$(names)" "DNS:localhost,DNS:homebridge-vm.local,IPAddress:127.0.0.1"

rm -rf "$C" && mkdir -p "$C/etc/nginx/sites-available"
cert_script
isnt "nothing is made when the Homebridge site config is not there" test -e "$SSL"

run_stage 03-nginx 01-run.sh
same "the nginx stage ends with code 0" "$STAGE_CODE" "0"
same "the certificate script is installed as a program (755)" "$(stat -c '%a' "$W/root/usr/local/sbin/nginx-homebridge-self-signed-cert")" "755"

finish
