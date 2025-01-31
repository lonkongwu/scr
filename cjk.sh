#!/bin/bash

# 定义日志文件路径
LOGS=(
    "/root/.pm2/logs/cysic-prover-error.log"
    "/root/.pm2/logs/cysic-prover1-error.log"
)
CONFIGS=(
    "/root/cysic-prover/config.yaml"
    "/root/cysic-prover1/config.yaml"
)
CONFIG_FILE="/root/wallet_config.txt"
LOG_OUTPUT="/root/cya_log.txt"

# 飞书 Webhook 地址
FEISHU_ADDRESS=""
SERVER_NAME="Cysic_Server1" # 修改为你的服务器名称

# 初始化钱包状态
WALLET1_FLAG=1
WALLET2_FLAG=1

# 日志记录函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_OUTPUT"
}

# 发送飞书消息函数
send_feishu_message() {
    local message=$1
    if [[ -z "$FEISHU_ADDRESS" ]]; then
        log "❌ 飞书 Webhook 地址未配置，无法发送消息。"
        return 1
    fi
    curl -s -X POST "$FEISHU_ADDRESS" \
        -H "Content-Type: application/json" \
        -d "{\"msg_type\": \"text\", \"content\": {\"text\": \"$message\"}}" || log "❌ 飞书消息发送失败。"
}

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "✅ 配置文件已加载: $CONFIG_FILE"
    else
        log "❌ 配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
}

# 获取当前运行的钱包地址和编号
get_current_wallet_info() {
    local group_number=$1
    local wallet_address=""
    local wallet_id=""

    if [ "$group_number" -eq 1 ]; then
        case $WALLET1_FLAG in
            1) wallet_address=$WALLET1_1; wallet_id=$WALLET1_1_ID ;;
            2) wallet_address=$WALLET1_2; wallet_id=$WALLET1_2_ID ;;
            3) wallet_address=$WALLET1_3; wallet_id=$WALLET1_3_ID ;;
            4) wallet_address=$WALLET1_4; wallet_id=$WALLET1_4_ID ;;
            5) wallet_address=$WALLET1_5; wallet_id=$WALLET1_5_ID ;;
            6) wallet_address=$WALLET1_6; wallet_id=$WALLET1_6_ID ;;
        esac
    elif [ "$group_number" -eq 2 ]; then
        case $WALLET2_FLAG in
            1) wallet_address=$WALLET2_1; wallet_id=$WALLET2_1_ID ;;
            2) wallet_address=$WALLET2_2; wallet_id=$WALLET2_2_ID ;;
            3) wallet_address=$WALLET2_3; wallet_id=$WALLET2_3_ID ;;
            4) wallet_address=$WALLET2_4; wallet_id=$WALLET2_4_ID ;;
            5) wallet_address=$WALLET2_5; wallet_id=$WALLET2_5_ID ;;
            6) wallet_address=$WALLET2_6; wallet_id=$WALLET2_6_ID ;;
        esac
    fi

    echo "$wallet_address" "$wallet_id"
}

# 切换到下一个钱包
switch_to_next_wallet() {
    local group_number=$1
    local config_file=${CONFIGS[$((group_number - 1))]}
    local current_wallet=""
    local current_id=""
    local new_address=""
    local new_id=""

    read current_wallet current_id < <(get_current_wallet_info "$group_number")

    # 循环更新钱包地址
    if [ "$group_number" -eq 1 ]; then
        case $WALLET1_FLAG in
            1) new_address=$WALLET1_2; new_id=$WALLET1_2_ID; WALLET1_FLAG=2 ;;
            2) new_address=$WALLET1_3; new_id=$WALLET1_3_ID; WALLET1_FLAG=3 ;;
            3) new_address=$WALLET1_4; new_id=$WALLET1_4_ID; WALLET1_FLAG=4 ;;
            4) new_address=$WALLET1_5; new_id=$WALLET1_5_ID; WALLET1_FLAG=5 ;;
            5) new_address=$WALLET1_6; new_id=$WALLET1_6_ID; WALLET1_FLAG=6 ;;
            6) new_address=$WALLET1_1; new_id=$WALLET1_1_ID; WALLET1_FLAG=1 ;;
        esac
    elif [ "$group_number" -eq 2 ]; then
        case $WALLET2_FLAG in
            1) new_address=$WALLET2_2; new_id=$WALLET2_2_ID; WALLET2_FLAG=2 ;;
            2) new_address=$WALLET2_3; new_id=$WALLET2_3_ID; WALLET2_FLAG=3 ;;
            3) new_address=$WALLET2_4; new_id=$WALLET2_4_ID; WALLET2_FLAG=4 ;;
            4) new_address=$WALLET2_5; new_id=$WALLET2_5_ID; WALLET2_FLAG=5 ;;
            5) new_address=$WALLET2_6; new_id=$WALLET2_6_ID; WALLET2_FLAG=6 ;;
            6) new_address=$WALLET2_1; new_id=$WALLET2_1_ID; WALLET2_FLAG=1 ;;
        esac
    fi

    log "✅ 当前钱包: $current_wallet (编号: $current_id)，切换到: $new_address (编号: $new_id)"

    # 停止服务并更新配置
    local service_name="cysic-prover"
    [[ $group_number -eq 2 ]] && service_name="cysic-prover1"
    pm2 stop "$service_name"
    sed -i "s|claim_reward_address: \".*\"|claim_reward_address: \"$new_address\"|" "$config_file"
    > "${LOGS[$((group_number - 1))]}"
    pm2 start "$service_name"

    send_feishu_message "服务器: $SERVER_NAME ✅ 组${group_number}，钱包地址 $current_wallet 编号 $current_id 完成了任务，新的地址为 $new_address 编号 $new_id"
}

# 检查组任务完成状态
check_group() {
    local group_number=$1
    local log_file=${LOGS[$((group_number - 1))]}
    local count=$(grep -c "resp: code: 0" "$log_file")
    local current_wallet=""
    local current_id=""

    # 获取当前钱包地址和编号
    read current_wallet current_id < <(get_current_wallet_info "$group_number")
    log "组${group_number}当前钱包地址: $current_wallet (编号: $current_id)"
    log "组${group_number}日志中 'resp: code: 0' 的计数: $count"

    # 检测日志中的条件
    if grep -q "submit taskData" "$log_file"; then
        log "组${group_number}日志中检测到 'submit taskData'"

        if [ "$count" -ge 3 ]; then
            switch_to_next_wallet "$group_number"
        fi
    fi
}

# 主程序
main() {
    load_config

    # 清空日志
    > "${LOGS[0]}"
    > "${LOGS[1]}"
    log "✅ 日志文件已清空，请确保没有正在执行的任务。"

    while true; do
        for group in {1..2}; do
            check_group "$group"
        done
        sleep 60
    done
}

main
