#!/bin/bash
# ==============================================================================
# 脚本名称: cron_check.sh
# 功能描述: 1. 定时逻辑备份 MySQL 数据库并打包压缩
#           2. 提取 Nginx、MySQL、Java 后端过去 24 小时的异常与错误日志
#           3. 自动清理 7 天前的历史备份与日志（容量管理）
# ==============================================================================

# 1. 基础变量配置
BASE_DIR="/opt/my-project"
BACKUP_DIR="${BASE_DIR}/mysql/backup"
LOG_EXTRACT_DIR="${BASE_DIR}/inspection_logs"

# 容器名称配置（需与 docker-compose.yml 中的 container_name 一致）
MYSQL_CONTAINER="mysql-db"
NGINX_CONTAINER="nginx-proxy"
JAVA_CONTAINER="java-app"

# 数据库配置
MYSQL_USER="root"
MYSQL_PASSWORD="ubuntu@123" # 替换为你的真实密码
DATABASE_NAME="reading_club"

# 时间变量
DATE=$(date + %Y%m%d)
DATE_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# 创建所需目录
mkdir -p "${BACKUP_DIR}"
mkdir -p "${LOG_EXTRACT_DIR}"

# 定义脚本自身运行日志输出函数
log_info() {
    echo "[${DATE_TIME}] [INFO] $1"
}

log_error() {
    echo "[${DATE_TIME}] [ERROR] $1" >&2
}

echo "======================= 开始执行每日全栈巡检与备份任务 ======================="

# ==============================================================================
# 任务一：MySQL 数据库物理/逻辑备份
# ==============================================================================
log_info "开始备份数据库: ${DATABASE_NAME}..."
BACKUP_FILE="${BACKUP_DIR}/${DATABASE_NAME}_${DATE}.sql.gz"

# 使用临时环境变量传递密码，消除命令行不安全警告
docker exec -i -e MYSQL_PWD="${MYSQL_PASSWORD}" ${MYSQL_CONTAINER} \
    mysqldump -u"${MYSQL_USER}" "${DATABASE_NAME}" 2>/tmp/dump_err.log | gzip > "${BACKUP_FILE}"

# 检查备份结果（运维核心习惯：判断上一个命令的退出状态 $?）
if [ $? -eq 0 ] && [ -s "${BACKUP_FILE}" ]; then
    log_info "数据库备份成功 -> ${BACKUP_FILE} (文件大小: $(ls -lh ${BACKUP_FILE} | awk '{print $5}'))"
    rm -f /tmp/dump_err.log
else
    log_error "数据库备份失败！错误详情: $(cat /tmp/dump_err.log)"
fi

# ==============================================================================
# 任务二：全栈日志提取（提取过去 24 小时内的关键异常）
# ==============================================================================
log_info "开始提取日志中的异常与错误信息..."
NGINX_LOG_FILE="${LOG_EXTRACT_DIR}/nginx_error_${DATE}.log"
MYSQL_LOG_FILE="${LOG_EXTRACT_DIR}/mysql_error_${DATE}.log"
JAVA_LOG_FILE="${LOG_EXTRACT_DIR}/java_exception_${DATE}.log"

# 1. 提取 Nginx 过去 24 小时的异常日志（重点关注 50x 错误、拒绝连接等）
docker logs --since 24h ${NGINX_CONTAINER} 2>&1 | grep -E -i "error|warn|crit|502|504|500" > "${NGINX_LOG_FILE}"
log_info "Nginx 异常日志提取完成 -> ${NGINX_LOG_FILE}"

# 2. 提取 MySQL 过去 24 小时的错误与警告日志
docker logs --since 24h ${MYSQL_CONTAINER} 2>&1 | grep -E -i "error|warning|failed" > "${MYSQL_LOG_FILE}"
log_info "MySQL 异常日志提取完成 -> ${MYSQL_LOG_FILE}"

# 3. 【新增】提取 Java 后端服务过去 24 小时的严重异常与堆栈报错
# (运维技巧：Java 常见错误包含 Exception、NullPointer、Timeout、Error 等)
docker logs --since 24h ${JAVA_CONTAINER} 2>&1 | grep -E -i "exception|error|failed|nullpointer|timeout|caused by" > "${JAVA_LOG_FILE}"
log_info "Java 后端异常日志提取完成 -> ${JAVA_LOG_FILE}"

# ==============================================================================
# 任务三：自动化容量管理（清理 7 天前的历史备份和巡检日志，防止撑爆磁盘）
# ==============================================================================
log_info "开始清理 7 天前的历史过时数据..."

# 清理旧备份，-exec 表示对find找到的每一个匹配文件执行后面的命令,把当前找到的文件路径替换到 {} 位置，然后执行 rm -f 删除它。\表示结束标记转义
find "${BACKUP_DIR}" -mtime +7 -name "*.sql.gz" -exec rm -f {} \;
# 清理旧巡检日志（包含了 nginx、mysql、java 的所有历史 .log 文件）
find "${LOG_EXTRACT_DIR}" -mtime +7 -name "*.log" -exec rm -f {} \;

log_info "历史数据清理完毕。"
echo "==================== 巡检与备份任务全部结束 ===================="

