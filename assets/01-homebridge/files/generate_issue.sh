#!/bin/bash
# Read original /etc/issue content
ISSUE_CONTENT=$(cat /usr/local/etc/issue.template)
IP=$(ip addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)
# Generate QR code and combine with /etc/issue
paste -d ' ' <(qrencode -t ANSIUTF8 http://${IP}/) <(echo "$ISSUE_CONTENT" | pr -t -w 80) > /etc/issue