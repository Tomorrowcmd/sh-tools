#!/bin/bash

# ==========================================
# 服务器系统信息巡检脚本
# ==========================================

# 设置颜色输出，方便阅读
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m' # 恢复默认颜色

# 打印带颜色的分割线
print_line() {
    echo -e "${CYAN}==================================================${NC}"
}

print_header() {
    echo -e "${YELLOW}>>> $1${NC}"
}

echo ""
print_line
# -e 表示使用转移字符解析
echo -e "${GREEN}             服务器基础信息巡检报告             ${NC}"
print_line

# ------------------------------------------
# 1. 获取内存信息 (单位化为易读格式: G/M)
# ------------------------------------------
mem_total=$(free -h | awk '/^Mem:/ {print $2}')
mem_used=$(free -h | awk '/^Mem:/ {print $3}')
mem_free=$(free -h | awk '/^Mem:/ {print $4}')

echo "总内存 (Total)       : $mem_total"
echo "已用内存 (Used)      : $mem_used"
echo "剩余内存 (Free)      : $mem_free"
echo ""

# ------------------------------------------
# 2. 获取磁盘信息 (以根目录 / 为基准)
# ------------------------------------------
print_header "磁盘信息 (根目录 /)"
# NR==2 表示只处理第二行数据，即根目录的磁盘信息
disk_total=$(df -h / | awk 'NR==2 {print $2}')
disk_used=$(df -h / | awk 'NR==2 {print $3}')
disk_free=$(df -h / | awk 'NR==2 {print $4}')
disk_percent=$(df -h / | awk 'NR==2 {print $5}')

echo "磁盘总大小 (Total)   : $disk_total"
echo "已用磁盘 (Used)      : $disk_used"
echo "剩余磁盘 (Free)      : $disk_free"
echo "磁盘使用率           : $disk_percent"
echo ""


# ------------------------------------------
# 3 & 4. 获取操作系统名称与版本
# ------------------------------------------
print_header "操作系统信息"
if [ -f /etc/os-release ]; then
    # tr -d '"' 用于删除引号，确保输出干净, tr 主要用户文本处理，用于字符替换或删除
    os_name=$(grep -E '^NAME=' /etc/os-release | awk -F= '{print $2}' | tr -d '"')
    os_version=$(grep -E '^VERSION=' /etc/os-release | awk -F= '{print $2}' | tr -d '"')
else
    os_name=$(cat /etc/issue | head -n 1 | awk '{print $1}')
    os_version=$(cat /etc/issue | head -n 1 | awk '{print $2}')
fi

echo "操作系统名称         : $os_name"
echo "系统版本号           : $os_version"
echo ""

# ------------------------------------------
# 5 & 6. 获取 CPU 信息
# ------------------------------------------
print_header "CPU 信息"
# CPU型号 (去重并去除头部空格)
# -m 1 表示只取第一行，避免多核CPU输出多行，限制最大匹配行
cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^[ \t]*//')
# 如果是某些ARM架构，可能取不到 model name，尝试 fallback
# -z 表示检查变量是否为空，如果为空则执行后面的命令，用于判断字符串的运算符
[ -z "$cpu_model" ] && cpu_model=$(grep -m 1 "Hardware" /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^[ \t]*//')

# 逻辑核心总数
cpu_logical=$(grep -c "processor" /proc/cpuinfo)

# 物理CPU核数 (物理插槽数)
cpu_physical=$(grep "physical id" /proc/cpuinfo | sort -u | wc -l)

# 虚拟机环境下可能没有 physical id，默认为 1
[ "$cpu_physical" -eq 0 ] && cpu_physical=1

# 每个物理CPU的逻辑核心数
cpu_cores_per_phys=$((cpu_logical / cpu_physical))

echo "CPU 型号             : $cpu_model"
echo "物理 CPU 总数        : $cpu_physical"
echo "单 CPU 逻辑核心数    : $cpu_cores_per_phys"
echo "CPU 逻辑核心总数     : $cpu_logical"
echo ""

# ------------------------------------------
# 附加功能：其他实用运维指标
# ------------------------------------------
print_header "其他运维指标 (Bonus)"

# 系统运行时间
up_tinme=$(uptime -p | sed 's/up //')
# 系统平均负载 (1分钟, 5分钟, 15分钟)
load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
# 本机主要内网 IP
ip_addr=$(hostname -I | awk '{print $1}')
# 当前登录终端数
login_users=$(who | wc -l)

echo "系统运行时间 (Uptime): $up_time"
echo "平均负载 (Load)      : $load_avg"
echo "内网 IP 地址         : $ip_addr"
echo "当前登录终端数       : $login_users"

print_line
echo ""