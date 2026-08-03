#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 sudo 运行此脚本。" >&2
  exit 1
fi

if [[ $# -gt 1 ]]; then
  echo "用法: sudo ./scripts/enable-https.sh [Let's Encrypt 通知邮箱]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DOMAIN=zhuzhiliao.aimfor.top
NGINX_SITE=/etc/nginx/sites-available/zhuzhiliao.aimfor.top

account_args=(--register-unsafely-without-email)
if [[ $# -eq 1 ]]; then
  account_args=(--email "$1")
fi

certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --domain "${DOMAIN}" \
  "${account_args[@]}" \
  --agree-tos \
  --non-interactive

install -m 0644 "${SOURCE_DIR}/deploy/nginx-tls.conf" "${NGINX_SITE}"
nginx -t
systemctl reload nginx
certbot renew --cert-name "${DOMAIN}" --dry-run

echo "HTTPS 与自动续期验证完成：https://${DOMAIN}/api/stats"
