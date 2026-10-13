#!/usr/bin/env bash
set -Eeuo pipefail
# 安装 jdk 的命令
# dnf install ./jdk-17.0.20.1_linux-x64_bin.rpm

# ============================================================
# Kafka 自动安装脚本
# 功能：环境检查、解压安装、配置 Kafka、初始化 KRaft、
#       创建 systemd 服务、启动 Kafka 并设置开机自启
# ============================================================

# 检查是否使用 root 执行
if (( EUID != 0 )); then
    echo "错误：请使用 root 用户执行此脚本"
    exit 1
fi

# 获取当前脚本所在目录的绝对路径
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ================= 定义需要的变量 ==========================

# Kafka 安装包名称
KAFKA_TAZ="kafka_2.13-4.3.1.tgz"

# Kafka 解压目录
KAFKA_INSTALL="/usr/local"

# Kafka 软链接路径
KAFKA_INDIR="/usr/local/kafka"

# Kafka 配置文件
KAFKA_CONFIG="$KAFKA_INDIR/config/server.properties"

# Kafka 数据目录
KAFKA_DATA_DIR="/var/lib/kafka/data"

# systemd 服务文件
KAFKA_SERVICE="/etc/systemd/system/kafka.service"

# ============================================================
# 第一阶段：安装前检查环境
# ============================================================

echo "========== 1. 检查运行环境 =========="

# 1. 检查 Java 是否安装
if ! command -v java >/dev/null 2>&1; then
    echo "错误：未检测到 Java，请先安装 JDK 17 或更高版本"
    exit 1
fi

# 2. 获取 Java 版本
java_version=$(java -version 2>&1 |
    awk -F '"' '/version/ {print $2; exit}')

if [[ -z "$java_version" ]]; then
    echo "错误：无法获取 Java 版本信息"
    exit 1
fi

# 3. 解析 Java 主版本号
# 兼容 1.8.0_xxx 和 17.0.x、21.0.x 等格式
# #号去掉第一个前缀，%%匹配第一个点符号去掉后面的内容拿到版本号
if [[ "$java_version" == 1.* ]]; then
    major_version="${java_version#1.}"
    major_version="${major_version%%.*}"
else
    major_version="${java_version%%.*}"
fi

# 4. 判断主版本号是否为数字，且大于等于 17
if ! [[ "$major_version" =~ ^[0-9]+$ ]] ||
   (( major_version < 17 )); then
    echo "错误：当前 Java 版本为 ${java_version}"
    echo "要求：JDK 17 或更高版本"
    exit 1
fi

echo "Java 版本检查通过：$java_version"

# 5. 检查 Kafka 安装包
KAFKA_PACKAGE="$SCRIPT_DIR/$KAFKA_TAZ"

if [[ ! -f "$KAFKA_PACKAGE" ]]; then
    echo "错误：Kafka 安装包不存在：$KAFKA_PACKAGE"
    exit 1
fi

echo "Kafka 安装包检查通过：$KAFKA_PACKAGE"

# 6. 检查目标安装路径，防止覆盖现有安装
KAFKA_DIR="${KAFKA_TAZ%.tgz}"
KAFKA_REAL_DIR="$KAFKA_INSTALL/$KAFKA_DIR"

if [[ -e "$KAFKA_INDIR" || -L "$KAFKA_INDIR" ]]; then
    echo "错误：Kafka 软链接或安装路径已经存在：$KAFKA_INDIR"
    echo "请检查现有安装后再执行，避免覆盖数据"
    exit 1
fi

if [[ -e "$KAFKA_REAL_DIR" ]]; then
    echo "错误：Kafka 解压目录已经存在：$KAFKA_REAL_DIR"
    echo "请检查现有目录后再执行"
    exit 1
fi

echo "环境检查通过"

# ============================================================
# 第二阶段：解压 Kafka 并创建软链接
# ============================================================

echo
echo "========== 2. 安装 Kafka =========="

tar -zxf "$KAFKA_PACKAGE" -C "$KAFKA_INSTALL"

if [[ ! -d "$KAFKA_REAL_DIR" ]]; then
    echo "错误：Kafka 解压目录不存在：$KAFKA_REAL_DIR"
    exit 1
fi

# 创建软链接
ln -s "$KAFKA_REAL_DIR" "$KAFKA_INDIR"

echo "Kafka 解压成功：$KAFKA_REAL_DIR"
echo "Kafka 软链接创建成功：$KAFKA_INDIR"

# ============================================================
# 第三阶段：获取本机 IP
# ============================================================

echo
echo "========== 3. 获取本机 IP =========="

# 优先获取默认出站路由对应的本机 IP
LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null |
    awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}') || true

# 如果没有获取到，尝试使用 hostname -I
if [[ -z "$LOCAL_IP" ]]; then
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}') || true
fi

if [[ -z "$LOCAL_IP" ]]; then
    echo "错误：无法获取本机 IP 地址"
    exit 1
fi

echo "获取到本机 IP：$LOCAL_IP"

# ============================================================
# 第四阶段：创建数据目录并修改 Kafka 配置
# ============================================================

echo
echo "========== 4. 修改 Kafka 配置 =========="

# 1. 创建 Kafka 数据目录
if ! mkdir -p "$KAFKA_DATA_DIR"; then
    echo "错误：创建 Kafka 数据目录失败：$KAFKA_DATA_DIR"
    exit 1
fi

echo "Kafka 数据目录已创建：$KAFKA_DATA_DIR"

# 2. 检查配置文件
if [[ ! -f "$KAFKA_CONFIG" ]]; then
    echo "错误：Kafka 配置文件不存在：$KAFKA_CONFIG"
    exit 1
fi

# 3. 备份原始配置文件
BACKUP_TIME=$(date +%Y%m%d%H%M%S)
KAFKA_CONFIG_BAK="${KAFKA_CONFIG}.bak.${BACKUP_TIME}"

cp -a "$KAFKA_CONFIG" "$KAFKA_CONFIG_BAK"

echo "配置文件备份成功：$KAFKA_CONFIG_BAK"

# 4. 修改监听地址
# Kafka 客户端监听所有 IPv4 网卡
# Controller 端口仅监听本机，适用于单节点部署
sed -i -E \
    's|^[[:space:]]*listeners[[:space:]]*=.*|listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://127.0.0.1:9093|' \
    "$KAFKA_CONFIG"

# 5. 修改对外公布地址
# 客户端通过本机实际 IP 访问 Kafka
sed -i -E \
    "s|^[[:space:]]*advertised\.listeners[[:space:]]*=.*|advertised.listeners=PLAINTEXT://${LOCAL_IP}:9092|" \
    "$KAFKA_CONFIG"

# sed -i \
#     "s|PLAINTEXT:\/\/localhost:9092|PLAINTEXT://${LOCAL_IP}:9092|" \
#     "$KAFKA_CONFIG"

# 6. 修改 Kafka 数据目录
sed -i -E \
    "s|^[[:space:]]*log\.dirs[[:space:]]*=.*|log.dirs=${KAFKA_DATA_DIR}|" \
    "$KAFKA_CONFIG"


# 7. 检查配置修改结果
echo
echo "========== Kafka 配置检查 =========="

grep -E '^(listeners|advertised\.listeners|log\.dirs)=' \
    "$KAFKA_CONFIG"

echo
echo "Kafka 配置修改完成"

# ============================================================
# 第五阶段：初始化 KRaft 存储
# ============================================================

echo
echo "========== 5. 初始化 KRaft 存储 =========="

# 重要：必须先修改配置，再格式化存储目录
# 避免初始化到默认的 /tmp/kraft-combined-logs

KAFKA_CLUSTER_ID=$(
    "$KAFKA_INDIR/bin/kafka-storage.sh" random-uuid
)

if [[ -z "$KAFKA_CLUSTER_ID" ]]; then
    echo "错误：生成 Kafka Cluster ID 失败"
    exit 1
fi

echo "Kafka Cluster ID：$KAFKA_CLUSTER_ID"

# 格式化存储目录
# --standalone 适用于单节点 KRaft 初始化
"$KAFKA_INDIR/bin/kafka-storage.sh" format \
    -t "$KAFKA_CLUSTER_ID" \
    -c "$KAFKA_CONFIG" \
    --standalone

echo "KRaft 存储初始化完成"

# ============================================================
# 第六阶段：创建 systemd 服务
# ============================================================

echo
echo "========== 6. 创建 Kafka systemd 服务 =========="

cat > "$KAFKA_SERVICE" <<EOF
[Unit]
Description=Apache Kafka (KRaft)
Documentation=http://kafka.apache.org/documentation.html
After=network.target

[Service]
Type=simple
User=root
ExecStart=${KAFKA_INDIR}/bin/kafka-server-start.sh ${KAFKA_CONFIG}
ExecStop=${KAFKA_INDIR}/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

if [[ ! -f "$KAFKA_SERVICE" ]]; then
    echo "错误：Kafka systemd 服务文件创建失败"
    exit 1
fi

echo "Kafka systemd 服务文件创建成功：$KAFKA_SERVICE"

# 重新加载 systemd 配置
systemctl daemon-reload

echo "systemd 配置重载成功"

# ============================================================
# 第七阶段：启动 Kafka 并设置开机自启
# ============================================================

echo
echo "========== 7. 启动 Kafka 服务 =========="

systemctl enable --now kafka

# 检查服务状态
if systemctl is-active --quiet kafka; then
    echo "Kafka 服务启动成功"
else
    echo "错误：Kafka 服务未处于 active 状态"
    echo "请执行以下命令查看日志："
    echo "journalctl -u kafka -n 100 --no-pager"
    exit 1
fi

# ============================================================
# 安装完成
# ============================================================

echo
echo "============================================"
echo "Kafka 安装与配置完成"
echo "Java 版本：$java_version"
echo "Kafka 版本目录：$KAFKA_REAL_DIR"
echo "Kafka 软链接：$KAFKA_INDIR"
echo "客户端连接地址：${LOCAL_IP}:9092"
echo "Kafka 数据目录：$KAFKA_DATA_DIR"
echo "systemd 服务：$KAFKA_SERVICE"
echo "============================================"

echo
echo "常用管理命令："
echo "启动服务：systemctl start kafka"
echo "停止服务：systemctl stop kafka"
echo "重启服务：systemctl restart kafka"
echo "查看状态：systemctl status kafka"
echo "查看日志：journalctl -u kafka -f"