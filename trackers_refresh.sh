#!/bin/bash

# 配置文件路径
CONF_PATH="/etc/aria2/aria2.conf"

# Tracker 列表 URL 数组
# 建议：如果不想脚本跑太久，可以将下方链接中的 _all 改为 _best (精选列表)
URLS=(
    "https://cdn.jsdelivr.net/gh/XIU2/TrackersListCollection@master/all.txt"
    "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_all.txt"
    "https://cdn.jsdelivr.net/gh/ngosang/trackerslist@master/trackers_all_ip.txt"
    "https://trackerslist.com/all.txt"
)

# 临时文件
TMP_FILE=$(mktemp)
VALID_FILE=$(mktemp)

# 1. 下载并聚合所有 Tracker
echo "1. 正在下载 Tracker 列表..."
for url in "${URLS[@]}"; do
    curl -sL --connect-timeout 10 -m 20 "$url" >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"
done

# 2. 初步清洗：去空行、去重
echo "2. 正在清洗重复数据..."
# 暂存清洗后的列表
CLEAN_LIST=$(cat "$TMP_FILE" | tr -d '\r' | awk 'NF' | sort -u)

# 3. 并发验证 (核心优化部分)
echo "3. 正在验证 Tracker 有效性 (并发 Ping)..."

# 定义并发数量 (根据路由器/设备性能调整，建议 20-50)
MAX_JOBS=40

# 定义验证函数
check_tracker() {
    local url=$1
    # 提取域名或IP：
    # 1. 删除 :// 前面的协议
    # 2. 删除 / 后面的路径
    # 3. 删除 : 后面的端口
    local host=$(echo "$url" | sed -E 's/^[a-z]+:\/\///; s/\/.*//; s/:.*//')
    
    # Ping 测试
    # -c 1: 只发1个包
    # -W 1: 超时等待1秒 (Linux标准ping) 或 -t 1 (某些嵌入式ping)
    # 注意：这里使用 ping -c 1 -W 1 兼容大多数 Linux
    if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
        echo "$url" >> "$VALID_FILE"
        # 可选：打印进度点
        echo -n "."
    fi
}

# 循环处理
for url in $CLEAN_LIST; do
    # 放入后台执行
    check_tracker "$url" &
    
    # 进程控制：如果后台任务数 >= MAX_JOBS，则等待任意一个结束
    # read -u 这里的逻辑比较复杂，使用 job 控制更通用
    if [[ $(jobs -r -p | wc -l) -ge $MAX_JOBS ]]; then
        wait -n 2>/dev/null || wait # 等待任意一个后台任务结束
    fi
done

# 等待所有剩余任务完成
wait
echo -e "\n验证完成。"

# 4. 再次去重并格式化
# 因为多线程写入可能有极低概率的格式问题，再次 sort -u 确保万无一失
FINAL_LIST=$(cat "$VALID_FILE" | sort -u | paste -sd "," -)

# 清理临时文件
rm -f "$TMP_FILE" "$VALID_FILE"

# 5. 检查结果
if [ -z "$FINAL_LIST" ]; then
    echo "错误：没有有效的 Tracker (所有 Ping 都失败了)。"
    exit 1
fi

COUNT=$(echo "$FINAL_LIST" | tr ',' '\n' | wc -l)
echo "有效 Tracker 数量: $COUNT"

# 6. 更新配置文件
if [ -f "$CONF_PATH" ]; then
    echo "正在写入 aria2.conf..."
    sed -i "s|^bt-tracker=.*|bt-tracker=${FINAL_LIST}|g" "$CONF_PATH"
    echo "更新成功！"
    
    # 重启服务 (请根据实际情况取消注释)
    # /etc/init.d/aria2 restart
else
    echo "错误：找不到配置文件 $CONF_PATH"
    exit 1
fi
