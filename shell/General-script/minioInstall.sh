#!/bin/bash

set -e  # 出错自动退出

cd /opt
# minio_tar="minio-20250907161309.0.0-1.x86_64.rpm"
minio_tar="minio-20231111081441.0.0.x86_64.rpm"
# minio_tar="minio-20231111081441.0.0.aarch64.rpm"


rpm -ivh ${minio_tar}

install_path="/usr/local/bin/minio"

if [ -f "$install_path" ]; then
  echo "MinIO 已经安装"
else
  echo "MinIO 未安装"
fi
chmod +x /usr/local/bin/minio

mkdir -p /data/minio/data
mkdir -p /data/minio/config
echo "已创建好存放目录"

touch /etc/systemd/system/minio.service

cat > /etc/systemd/system/minio.service <<EOF
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/
Wants=network-online.target
After=network-online.target

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/minio server /data/minio/data \
    --config-dir /data/minio/config \
    --address ":9000" \
    --console-address ":9010"
Restart=always
LimitNOFILE=65536

EnvironmentFile=-/etc/default/minio

[Install]
WantedBy=multi-user.target
EOF

touch /etc/default/minio

cat > /etc/default/minio <<'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
EOF

echo "已创建好自启动配置文件"

systemctl daemon-reload
echo "已更新服务"
echo "部署完毕"
echo "请启动minio服务：systemctl start minio.service"