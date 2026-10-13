#!/bin/bash

# ==========================================
# 变量配置区 (请根据实际情况修改)
# ==========================================
RPM_FILE="aistor-20260919170525.0.0-1.x86_64.rpm"
# 在这里填入你的免费授权key
LICENSE_KEY="eyJhbGciOiJFUzM4NCIsInR5cCI6IkpXVCJ9.eyJhaWQiOjAsImNhcCI6MCwiZmVhdHVyZXMiOlsiT2JqZWN0cyIsIlRhYmxlcyJdLCJpYXQiOjEuNzkxNzE5NjA5Njg5ODg3MzE0ZTksImlzcyI6InN1Ym5ldEBtaW4uaW8iLCJsaWQiOiJlOWE4MWU5MC1lM2Y0LTQ4ZjItODZiNy1jMjIxNTY5MzMwY2UiLCJub2RlcyI6MSwib3JnIjoiIiwicGxhbiI6IkZSRUUiLCJwcm9kdWN0IjoiQUlTdG9yIiwic3ViIjoiMzE1ODUxODI0MEBxcS5jb20iLCJ0cmlhbCI6ZmFsc2UsInZlciI6MX0.loM3zrzK5sKvX1np7WHtgseBQGccB7iUziCtj7dNLrtnNDGgs-Rv3Axufu3xjgHpFW4SqhAJrhhRMju7P1FFbyoCXNNOOMZFsuy_e5VQ7QPcX9zCryfVEX5DXeQ5hJ8w"  

# 系统与目录配置
MINIO_LICENSE_DIR="/opt/minio"
MINIO_LICENSE_FILE="${MINIO_LICENSE_DIR}/minio.license"
DATA_DIR="/mnt/aistor_data"
MINIO_USER="minio-user"
MINIO_GROUP="minio-user"
SERVICE_NAME="minio" # 如果定制包的服务名是 aistor，请改为 "aistor"

# 配置文件路径及账密配置 (新增项)
MINIO_DEFAULT_CONF="/etc/default/minio"
MINIO_ENV_CONF="/etc/minio/config.env"
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"

# ==========================================
# 1. 前置检查
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 用户或 sudo 执行此脚本。"
  exit 1
fi

if [ ! -f "$RPM_FILE" ]; then
  echo "❌ 错误: 找不到安装包 $RPM_FILE，请确保它与此脚本在同一目录下。"
  exit 1
fi

# ==========================================
# 2. 停止并清理旧环境
# ==========================================
echo "🔄 正在停止 $SERVICE_NAME 服务..."
systemctl stop $SERVICE_NAME 2>/dev/null

echo "🗑️ 正在卸载旧版本 (如果有)..."
# 假设旧包名包含 aistor 或 minio，忽略卸载错误
dnf remove -y aistor minio 2>/dev/null

# ==========================================
# 3. 安装新版本 RPM 包
# ==========================================
echo "📦 正在安装 $RPM_FILE ..."
dnf install -y "./$RPM_FILE"

# ==========================================
# 4. 配置运行环境、License 及 追加配置文件
# ==========================================
echo "🔑 配置 License 授权文件..."
mkdir -p "$MINIO_LICENSE_DIR"
echo "$LICENSE_KEY" > "$MINIO_LICENSE_FILE"

echo "📝 追加配置到 $MINIO_DEFAULT_CONF ..."
mkdir -p $(dirname "$MINIO_DEFAULT_CONF")
cat <<EOF >> "$MINIO_DEFAULT_CONF"
MINIO_LICENSE="${MINIO_LICENSE_FILE}"
MINIO_VOLUMES="${DATA_DIR}"
EOF

echo "📝 追加配置到 $MINIO_ENV_CONF ..."
mkdir -p $(dirname "$MINIO_ENV_CONF")
cat <<EOF >> "$MINIO_ENV_CONF"
MINIO_ROOT_USER=${MINIO_ROOT_USER}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
EOF

echo "📂 检查并设置目录和文件权限..."
# 确保数据目录存在
mkdir -p "$DATA_DIR"

# 统一赋予 minio-user 权限
chown -R $MINIO_USER:$MINIO_GROUP "$MINIO_LICENSE_DIR"
chown -R $MINIO_USER:$MINIO_GROUP "$DATA_DIR"
chown -R $MINIO_USER:$MINIO_GROUP $(dirname "$MINIO_ENV_CONF")
chown $MINIO_USER:$MINIO_GROUP "$MINIO_DEFAULT_CONF"

# 确保敏感文件权限安全，仅 minio-user 可读写
chmod 600 "$MINIO_LICENSE_FILE"
chmod 600 "$MINIO_ENV_CONF"

# ==========================================
# 5. 启动服务并检查状态
# ==========================================
echo "🚀 重新加载 systemd 并启动服务..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "✅ 安装与配置完成！"
echo "📊 当前服务状态:"
systemctl status $SERVICE_NAME --no-pager | head -n 10