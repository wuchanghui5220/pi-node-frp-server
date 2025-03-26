#!/bin/bash

# frp 服务器一键部署脚本
# 用于AWS服务器配置安全的frp服务端
# 生成frpserverinfo.txt文件便于Windows端配置

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出彩色信息
echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo_error "请使用root权限运行此脚本 (sudo bash $0)"
    exit 1
fi

# 检查必要命令是否存在
echo_info "检查必要命令..."
for cmd in curl wget openssl tar systemctl mktemp iptables grep; do
    if ! command -v $cmd &> /dev/null; then
        echo_error "必要命令 '$cmd' 未找到，尝试安装中..."
        
        # 尝试安装缺失的命令
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y $cmd
        elif command -v yum &> /dev/null; then
            yum install -y $cmd
        else
            echo_error "无法安装 '$cmd'。请手动安装后重试。"
            exit 1
        fi
        
        # 再次检查命令是否已安装
        if ! command -v $cmd &> /dev/null; then
            echo_error "无法安装 '$cmd'。请手动安装后重试。"
            exit 1
        fi
    fi
done

# 获取当前服务器的公网IP
echo_info "获取服务器公网IP..."
SERVER_IP=""
# 尝试多种方法获取公网IP
for IP_METHOD in "curl -s https://checkip.amazonaws.com" "wget -qO- https://checkip.amazonaws.com" "curl -s https://api.ipify.org" "curl -s https://ipecho.net/plain"; do
    if SERVER_IP=$($IP_METHOD 2>/dev/null) && [ -n "$SERVER_IP" ]; then
        echo_info "成功获取公网IP: $SERVER_IP"
        break
    fi
done

if [ -z "$SERVER_IP" ]; then
    echo_error "无法获取服务器公网IP，请手动输入:"
    read -p "服务器公网IP: " SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        echo_error "未提供IP地址，退出安装"
        exit 1
    fi
fi

# 创建临时工作目录
WORK_DIR=$(mktemp -d)
if [ ! -d "$WORK_DIR" ]; then
    echo_error "创建临时目录失败，退出安装"
    exit 1
fi

cd "$WORK_DIR" || {
    echo_error "无法进入临时目录，退出安装" 
    exit 1
}

echo_info "开始安装frp服务端..."

# 获取最新版本号
echo_info "获取frp最新版本..."
LATEST_VERSION=""

# 尝试使用curl获取最新版本
if command -v curl &> /dev/null; then
    LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "\K[^"]+')
fi

# 如果curl失败，尝试使用wget
if [ -z "$LATEST_VERSION" ] && command -v wget &> /dev/null; then
    LATEST_VERSION=$(wget -qO- https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "\K[^"]+')
fi

# 如果还是失败，使用默认版本
if [ -z "$LATEST_VERSION" ]; then
    LATEST_VERSION="v0.51.3" # 默认版本，如果无法获取最新版本
    echo_info "无法获取最新版本，使用默认版本 $LATEST_VERSION"
else
    echo_info "获取到最新版本: $LATEST_VERSION"
fi

# 下载并解压frp
echo_info "下载frp $LATEST_VERSION..."
DOWNLOAD_SUCCESS=false

# 尝试使用wget下载
if command -v wget &> /dev/null; then
    wget -q "https://github.com/fatedier/frp/releases/download/$LATEST_VERSION/frp_${LATEST_VERSION#v}_linux_amd64.tar.gz" -O frp.tar.gz
    if [ $? -eq 0 ]; then
        DOWNLOAD_SUCCESS=true
    else
        echo_info "使用wget下载失败，尝试使用curl..."
    fi
fi

# 如果wget失败，尝试使用curl
if [ "$DOWNLOAD_SUCCESS" = false ] && command -v curl &> /dev/null; then
    curl -s -L "https://github.com/fatedier/frp/releases/download/$LATEST_VERSION/frp_${LATEST_VERSION#v}_linux_amd64.tar.gz" -o frp.tar.gz
    if [ $? -eq 0 ]; then
        DOWNLOAD_SUCCESS=true
    else
        echo_info "使用curl下载失败..."
    fi
fi

# 如果所有下载方法都失败
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo_error "下载frp失败，请检查网络连接或手动下载"
    echo_info "您可以尝试手动下载: https://github.com/fatedier/frp/releases/download/$LATEST_VERSION/frp_${LATEST_VERSION#v}_linux_amd64.tar.gz"
    exit 1
fi

# 验证下载的文件
if [ ! -s frp.tar.gz ]; then
    echo_error "下载的文件为空，请检查网络连接"
    exit 1
fi

echo_info "解压frp..."
if ! tar -xzf frp.tar.gz; then
    echo_error "解压frp失败，文件可能已损坏"
    exit 1
fi

# 检查解压后的目录是否存在
if [ ! -d "frp_${LATEST_VERSION#v}_linux_amd64" ]; then
    echo_error "解压后的目录不存在，解压可能失败"
    exit 1
fi

cd "frp_${LATEST_VERSION#v}_linux_amd64" || {
    echo_error "无法进入解压后的目录"
    exit 1
}

# 验证frps二进制文件
if [ ! -f "frps" ]; then
    echo_error "frps文件不存在，下载或解压可能失败"
    exit 1
fi

# 生成随机token
TOKEN=$(openssl rand -base64 32)
if [ -z "$TOKEN" ]; then
    echo_error "生成安全令牌失败，使用备用方法..."
    # 备用令牌生成方法
    TOKEN=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)
    if [ -z "$TOKEN" ]; then
        echo_error "无法生成安全令牌，使用默认令牌"
        TOKEN="ThisIsADefaultTokenPleaseChangeIt_$(date +%s)"
    fi
fi
echo_info "已生成安全令牌"

# 创建目录
mkdir -p /etc/frp /var/log/frp || {
    echo_error "创建配置目录失败"
    exit 1
}

# 创建frps.ini配置文件
echo_info "创建frps配置文件..."
cat > frps.ini << EOF
[common]
bind_port = 7000
# 设置加密通信的TLS
tls_enable = true
# 强安全性认证令牌
token = $TOKEN
# 限制允许的端口范围
allow_ports = 31400-31409
# 日志配置
log_file = /var/log/frp/frps.log
log_level = info
log_max_days = 7
# 不向客户端发送详细错误信息（安全措施）
detailed_errors_to_client = false
EOF

# 移动文件到合适位置
echo_info "安装frps..."
cp -f frps /usr/local/bin/ || {
    echo_error "复制frps二进制文件失败"
    exit 1
}

cp -f frps.ini /etc/frp/ || {
    echo_error "复制frps配置文件失败"
    exit 1
}

chmod +x /usr/local/bin/frps || {
    echo_error "设置frps执行权限失败"
    exit 1
}

# 创建systemd服务文件
echo_info "创建systemd服务..."
cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=frps service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.ini
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
echo_info "启动frps服务..."
if ! systemctl daemon-reload; then
    echo_error "重新加载systemd失败"
    exit 1
fi

if ! systemctl enable frps; then
    echo_error "启用frps服务失败"
    exit 1
fi

if ! systemctl start frps; then
    echo_error "启动frps服务失败，请检查 journalctl -xe 了解详情"
    exit 1
fi

# 检查服务状态
if systemctl is-active --quiet frps; then
    echo_success "frps服务已成功启动!"
else
    echo_error "frps服务启动失败，请检查 journalctl -xe 了解详情"
    exit 1
fi

# 配置防火墙
echo_info "配置防火墙规则..."
FIREWALL_CONFIGURED=false

# 尝试使用ufw
if command -v ufw &> /dev/null && systemctl is-active --quiet ufw; then
    echo_info "使用ufw配置防火墙..."
    ufw allow 7000/tcp
    ufw allow 31400:31409/tcp
    echo_success "ufw防火墙规则已添加"
    FIREWALL_CONFIGURED=true
# 尝试使用firewalld
elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
    echo_info "使用firewalld配置防火墙..."
    firewall-cmd --permanent --add-port=7000/tcp
    firewall-cmd --permanent --add-port=31400-31409/tcp
    firewall-cmd --reload
    echo_success "firewalld防火墙规则已添加"
    FIREWALL_CONFIGURED=true
# 使用iptables
elif command -v iptables &> /dev/null; then
    echo_info "使用iptables配置防火墙规则..."
    
    # 添加iptables规则
    iptables -A INPUT -p tcp --dport 7000 -j ACCEPT
    for port in $(seq 31400 31409); do
        iptables -A INPUT -p tcp --dport $port -j ACCEPT
    done
    
    # 保存iptables规则
    if command -v iptables-save &> /dev/null; then
        echo_info "保存iptables规则..."
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4
        else
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            
            # 创建网络接口启动脚本以加载规则
            cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
EOF
            chmod +x /etc/network/if-pre-up.d/iptables
        fi
        
        # 安装iptables-persistent使规则持久化
        echo_info "尝试安装iptables-persistent以持久化防火墙规则..."
        if command -v apt-get &> /dev/null; then
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent || echo_info "无法安装iptables-persistent，防火墙规则可能在重启后丢失"
        fi
    else
        echo_info "无法保存iptables规则，防火墙规则可能在重启后丢失"
    fi
    
    echo_success "iptables防火墙规则已添加"
    FIREWALL_CONFIGURED=true
else
    echo_error "未找到支持的防火墙工具(ufw/firewalld/iptables)，请手动配置防火墙"
    echo_info "需要开放端口: 7000/tcp 和 31400-31409/tcp"
fi

if [ "$FIREWALL_CONFIGURED" = false ]; then
    echo_info "警告: 未配置防火墙规则，请确保端口 7000 和 31400-31409 已开放"
    echo_info "如果使用AWS，请在安全组中配置这些端口"
fi

# 创建监控脚本
echo_info "创建服务监控脚本..."
cat > /usr/local/bin/monitor-frps.sh << EOF
#!/bin/bash
if ! systemctl is-active --quiet frps; then
  echo "frps服务已停止，尝试重启..."
  systemctl restart frps
  # 可选：通过邮件通知管理员
  # echo "frps服务已停止并已重新启动。" | mail -s "frps服务警报" admin@example.com
fi
EOF
chmod +x /usr/local/bin/monitor-frps.sh || {
    echo_error "无法设置monitor-frps.sh执行权限"
    exit 1
}

# 添加到crontab，每5分钟检查一次
echo_info "设置定时监控任务..."
CRON_TMP=$(mktemp)
if ! (crontab -l 2>/dev/null || echo "") | grep -v "monitor-frps.sh" > "$CRON_TMP"; then
    echo_error "获取现有crontab失败"
    rm -f "$CRON_TMP"
    exit 1
fi

echo "*/5 * * * * /usr/local/bin/monitor-frps.sh" >> "$CRON_TMP"
if ! crontab "$CRON_TMP"; then
    echo_error "设置crontab失败"
    rm -f "$CRON_TMP"
    exit 1
fi
rm -f "$CRON_TMP"
echo_success "监控任务已设置"

# 创建frpserverinfo.txt文件
echo_info "生成客户端配置信息..."
CONFIG_FILE="frpserverinfo.txt"
cat > "$CONFIG_FILE" << EOF
==== FRP服务器配置信息 ====
服务器IP: $SERVER_IP
服务器端口: 7000
认证令牌: $TOKEN
TLS加密: 已启用
允许端口: 31400-31409
frp版本: ${LATEST_VERSION#v}

==== Windows客户端配置示例 ====
[common]
server_addr = $SERVER_IP
server_port = 7000
token = $TOKEN
tls_enable = true
log_file = C:\\frp\\frpc.log
log_level = info
log_max_days = 7

[pi-node-31400]
type = tcp
local_ip = 127.0.0.1
local_port = 31400
remote_port = 31400

[pi-node-31401]
type = tcp
local_ip = 127.0.0.1
local_port = 31401
remote_port = 31401

# 请为其余端口31402-31409添加类似配置

==== 安装说明 ====
1. 在Windows上下载frp: https://github.com/fatedier/frp/releases/download/$LATEST_VERSION/frp_${LATEST_VERSION#v}_windows_amd64.zip
2. 解压到C:\\frp目录
3. 创建C:\\frp\\frpc.ini文件，使用上述配置
4. 下载NSSM: https://nssm.cc/release/nssm-2.24.zip
5. 使用NSSM将frpc安装为Windows服务

==== 安全提示 ====
- 定期更改token（每3-6个月）
- 确保AWS安全组已开放7000和31400-31409端口
- 定期更新frp到最新版本

生成日期: $(date)
EOF

# 检查配置文件是否成功创建
if [ ! -f "$CONFIG_FILE" ]; then
    echo_error "创建配置信息文件失败"
    exit 1
fi

# 复制配置信息到用户主目录
if ! cp "$CONFIG_FILE" ~/frpserverinfo.txt; then
    echo_error "无法将配置信息复制到主目录"
    exit 1
fi
echo_success "配置信息已保存到 ~/frpserverinfo.txt"

# 清理
echo_info "清理临时文件..."
cd ~ || echo_error "无法返回用户主目录"
if [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR" || echo_error "无法删除临时工作目录 $WORK_DIR"
fi

echo
echo_success "FRP服务器端部署完成!"
echo_info "请查看 ~/frpserverinfo.txt 获取Windows客户端配置信息"
echo_info "确保AWS安全组已允许端口7000和31400-31409的入站流量"

# 显示服务状态
echo_info "服务状态:"
systemctl status frps --no-pager || echo_error "无法获取服务状态"
