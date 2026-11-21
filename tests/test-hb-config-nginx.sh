#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are meant: that text must reach the script under test as it is
# hb-config -> "Nginx Options" writes the nginx config. nginx itself must accept what it writes,
# on the nginx of Debian 13 and on the older one of Debian 12 (VMs made from an older image).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

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

hasnt "the tool no longer writes the misspelled header name" "$FILES/hb-config" 'X-Forward-For'

# hb-config -> Nginx Options. whiptail: "yes" to the question, and the given boxes ticked.
# make_config <nginx version> <ticked boxes, one per line>
make_config() {
  rm -rf "${W:?}/root" "${W:?}/calls.log" "${W:?}/bin"
  mkdir -p "$W/bin" "$W/root/etc/nginx/sites-available" "$W/root/usr/local/sbin" "$W/root/tmp"
  echo "${UI_PORT_FILE-8581}" > "$W/root/etc/hb-ui-port"
  printf '#!/bin/sh\nexit 0\n' > "$W/root/usr/local/sbin/nginx-homebridge-self-signed-cert"
  chmod +x "$W/root/usr/local/sbin/nginx-homebridge-self-signed-cert"
  printf '%s\n' "$2" > "$W/ticked"
  fake whiptail "case \"\$*\" in *--checklist*) cat \"$W/ticked\" >&2 ;; esac; exit 0"
  fake nginx "echo 'nginx version: nginx/$1' >&2"
  fake systemctl 'exit 0'
  hb_config do_configure_nginx
  MADE="$W/root/etc/nginx/sites-available/homebridge.local"
}

make_config 1.26.3 $'1\n2'
has "new nginx: the config turns HTTP/2 on with 'http2 on;'" "$MADE" "http2 on;"
has "new nginx: port 443 listens with ssl" "$MADE" "listen 443 ssl;"
has "port 80 is on when its box is ticked" "$MADE" "listen 80;"
has "the config proxies to the UI port" "$MADE" "proxy_pass                  http://127.0.0.1:8581;"
has "the config sends the X-Forwarded-For header" "$MADE" 'X-Forwarded-For $proxy_add_x_forwarded_for;'
has "nginx variables are written as they are" "$MADE" 'proxy_set_header            Host $host;'
check_with_nginx "nginx accepts the config hb-config writes, with no warning" "$MADE"
has "nginx is started again" "$W/calls.log" "systemctl restart nginx"

make_config 1.22.1 $'1\n2'
has "old nginx (Debian 12): the config uses 'listen 443 ssl http2;'" "$MADE" "listen 443 ssl http2;"
isnt "old nginx (Debian 12): no 'http2 on;' line, which it does not know" grep -q 'http2 on;' "$MADE"

make_config 1.25.1 $'1\n2'
has "nginx 1.25.1 is the first with 'http2 on;'" "$MADE" "http2 on;"
make_config 1.25.0 $'1\n2'
isnt "nginx 1.25.0 still gets the old form" grep -q 'http2 on;' "$MADE"
make_config 1.9.15 $'1\n2'
isnt "version numbers are compared as numbers (1.9 is older than 1.25)" grep -q 'http2 on;' "$MADE"

make_config 1.26.3 $'1\n2\n3'
has "with the redirect ticked, port 80 only redirects to https" "$MADE" 'return 302 https://$host$request_uri;'
check_with_nginx "nginx accepts the config with the redirect" "$MADE"

make_config 1.26.3 '2'
isnt "port 80 is off when its box is not ticked" grep -q 'listen 80;' "$MADE"
check_with_nginx "nginx accepts the config with https only" "$MADE"

UI_PORT_FILE='8581; evil' make_config 1.26.3 $'1\n2'
has "a port file with other text gives the default port" "$MADE" "proxy_pass                  http://127.0.0.1:8581;"
UI_PORT_FILE='9000' make_config 1.26.3 $'1\n2'
has "the port from the port file is used" "$MADE" "proxy_pass                  http://127.0.0.1:9000;"

# the script 20-hb-nginx-check must still find its line in the config hb-config writes
sed -e "s#/var/lib/homebridge/config.json#$W/config.json#g" -e "s#/etc/hb-ui-port#$W/root/etc/hb-ui-port#g" \
    -e "s#/etc/nginx/sites-available/homebridge.local#$MADE#g" "$FILES/20-hb-nginx-check" > "$W/check"
echo '{"platforms":[{"platform":"config","port":8090}]}' > "$W/config.json"
PATH="$W/bin:$PATH" bash "$W/check" > /dev/null 2>&1
has "the port script can update the config hb-config writes" "$MADE" "proxy_pass                  http://127.0.0.1:8090;"

finish
