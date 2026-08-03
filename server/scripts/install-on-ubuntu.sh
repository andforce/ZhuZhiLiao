#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "请使用 sudo 运行此脚本。" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR=/opt/zhuzhiliao-counter
SERVICE_USER=zhuzhiliao
NGINX_SITE=/etc/nginx/sites-available/zhuzhiliao.aimfor.top

if ! command -v node >/dev/null 2>&1; then
  echo "未找到 Node.js；请先安装 Node.js 20 或更高版本。" >&2
  exit 1
fi

node -e '
  const major = Number(process.versions.node.split(".")[0]);
  if (major < 20 || major > 26 || major === 21) process.exit(1);
' || {
  echo "Node.js 版本不兼容；支持 20、22、23、24、25、26。" >&2
  exit 1
}

missing_packages=()
command -v nginx >/dev/null 2>&1 || missing_packages+=(nginx)
command -v certbot >/dev/null 2>&1 || missing_packages+=(certbot)
dpkg-query -W -f='${Status}' build-essential 2>/dev/null | grep -q "install ok installed" \
  || missing_packages+=(build-essential)
command -v python3 >/dev/null 2>&1 || missing_packages+=(python3)

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_packages[@]}"
fi

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

install -d -o root -g root -m 0755 "${APP_DIR}" "${APP_DIR}/src"
install -m 0644 "${SOURCE_DIR}/package.json" "${SOURCE_DIR}/package-lock.json" "${APP_DIR}/"
install -m 0644 "${SOURCE_DIR}"/src/*.js "${APP_DIR}/src/"

cd "${APP_DIR}"
npm ci --omit=dev
chown -R root:root "${APP_DIR}"

install -m 0644 \
  "${SOURCE_DIR}/deploy/zhuzhiliao-counter.service" \
  /etc/systemd/system/zhuzhiliao-counter.service
install -d -m 0755 /var/www/certbot /etc/nginx/sites-available /etc/nginx/sites-enabled

if [[ -f /etc/letsencrypt/live/zhuzhiliao.aimfor.top/fullchain.pem ]]; then
  install -m 0644 "${SOURCE_DIR}/deploy/nginx-tls.conf" "${NGINX_SITE}"
else
  install -m 0644 "${SOURCE_DIR}/deploy/nginx-http.conf" "${NGINX_SITE}"
fi
ln -sfn "${NGINX_SITE}" /etc/nginx/sites-enabled/zhuzhiliao.aimfor.top

systemctl daemon-reload
systemctl enable zhuzhiliao-counter.service
systemctl restart zhuzhiliao-counter.service
chmod 0700 /var/lib/zhuzhiliao-counter
nginx -t
systemctl enable --now nginx
systemctl reload nginx

for _ in {1..20}; do
  if curl --fail --silent --show-error http://127.0.0.1:3210/healthz; then
    break
  fi
  sleep 0.25
done
curl --fail --silent --show-error http://127.0.0.1:3210/healthz >/dev/null
echo
echo "服务已启动。DNS 生效后运行 scripts/enable-https.sh 申请证书。"
