#!/bin/bash

set -e  # 出错自动退出

# ==========================================
# 变量配置区 (请根据实际情况修改)
# ==========================================
REDIS_VERSION="7.0.15"
REDIS_TAR="redis-${REDIS_VERSION}.tar.gz"
REDIS_PASS="111111"
LOG="/tmp/redis_build.log"

# 获取当前脚本所在的工作目录
WORK_DIR=$(pwd)
REDIS_SRC_DIR="${WORK_DIR}/redis-${REDIS_VERSION}"
CONF_DIR="/etc/redis"

# ==========================================
# 1. 前置检查
# ==========================================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 错误: 请使用 root 用户执行此脚本。"
  exit 1
fi

if [ ! -f "${WORK_DIR}/${REDIS_TAR}" ]; then
  echo "❌ 错误: 当前目录 (${WORK_DIR}) 找不到安装包 ${REDIS_TAR}"
  exit 1
fi

# ==========================================
# 2. 就地解压与编译安装
# ==========================================
echo "📦 正在解压 Redis ${REDIS_VERSION} 到当前目录..."
> "$LOG" # 初始化日志文件

# 直接在当前目录下解压
tar -zxf "${WORK_DIR}/${REDIS_TAR}" -C "${WORK_DIR}"
cd "${REDIS_SRC_DIR}"

echo "⚙️  开始编译源码，中途请不要中断...请稍后 (详细日志: $LOG)"
make > "$LOG" 2>&1

echo "⚙️  正在安装核心文件到系统环境..."
make install >> "$LOG" 2>&1

# ==========================================
# 3. 配置文件设置
# ==========================================
echo "📝 配置 Redis 环境与密码..."
mkdir -p "${CONF_DIR}"
cp redis.conf "${CONF_DIR}/"

# 设置密码
sed -i "s/^#\s*requirepass .*/requirepass ${REDIS_PASS}/" "${CONF_DIR}/redis.conf"

# 允许远程访问：直接匹配以 bind 开头的行并将其注释掉
sed -i 's/^bind /# bind /' "${CONF_DIR}/redis.conf"

# ==========================================
# 4. 配置 Systemd 服务
# ==========================================
echo "🚀 注册 Systemd 服务..."
# 注意: 因为开启了密码，ExecStop 必须带上密码参数(-a)
cat > /etc/systemd/system/redis.service <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=root
Group=root
ExecStart=/usr/local/bin/redis-server ${CONF_DIR}/redis.conf
ExecStop=/usr/local/bin/redis-cli -a ${REDIS_PASS} shutdown
Restart=always
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# 5. 启动服务
# ==========================================
systemctl daemon-reload
systemctl enable redis --now

echo "✅ Redis 部署完毕！"
echo "🔑 Redis 密码为: ${REDIS_PASS}"
echo "🌍 已注释本地 bind 限制，支持直接远程连接本机 6379 端口。"
echo "📂 源码目录位于: ${REDIS_SRC_DIR} (如不需要可手动删除)"
echo "📊 当前服务状态:"
systemctl status redis --no-pager | head -n 10