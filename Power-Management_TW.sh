#!/bin/bash
# ====================================================
# 增強版全能電源管理腳本 - Power Master v4.0
# 功能：電源操作 + 休眠管理 + 定時任務 + 系統信息 + Resume參數配置
# ====================================================

# 檢查 root 權限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "\033[31m✗ 此腳本需要 root 權限，請使用 sudo 執行\033[0m"
        exit 1
    fi
}

# 顯示倒計時
countdown() {
    local seconds=$1
    local action=$2
    
    # 設置文本顏色
    local color="\033[33m"  # 黃色
    local reset="\033[0m"
    
    # 捕獲 Ctrl+C 信號
    trap 'echo -e "\n${color}操作已取消${reset}"; sleep 1; return 1' INT
    
    while [ $seconds -gt 0 ]; do
        # 計算分鐘和秒
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        
        # 顯示動態倒計時
        echo -ne "${color}▶ ${action}倒計時: ${mins}分${secs}秒 (按 Ctrl+C 取消)${reset}\r"
        sleep 1
        seconds=$((seconds - 1))
    done
    
    # 重置信號捕獲
    trap - INT
    echo -ne "\033[K"  # 清除當前行
}

# 顯示系統信息
show_system_info() {
    echo -e "\n\033[34m[系統信息]\033[0m"
    echo "主機名: $(hostname)"
    echo "系統: $(lsb_release -ds 2>/dev/null || cat /etc/*release | head -n1)"
    echo "內核: $(uname -r)"
    echo "運行時間: $(uptime -p | sed 's/up //')"
}

# 顯示當前定時任務
show_scheduled_tasks() {
    local task=$(shutdown -c 2>&1 | grep -i 'shutdown scheduled')
    if [ -n "$task" ]; then
        echo -e "\n\033[33m⚠ 當前預定任務: $task\033[0m"
    fi
}

# 取消定時任務
cancel_scheduled() {
    shutdown -c >/dev/null 2>&1
    echo -e "\n\033[32m✓ 已取消所有預定的關機/重啟任務\033[0m"
    sleep 2
}

# 關機操作
power_off() {
    local delay=${1:-10}
    echo -e "\n\033[33m▶ 系統將在 ${delay} 秒後關機...\033[0m"
    
    # 顯示倒計時
    if countdown $delay "關機"; then
        echo -e "\033[31m▶ 系統關機中...\033[0m"
        shutdown -h now
    fi
}

# 重啟操作
reboot_system() {
    local delay=${1:-10}
    echo -e "\n\033[33m▶ 系統將在 ${delay} 秒後重啟...\033[0m"
    
    # 顯示倒計時
    if countdown $delay "重啟"; then
        echo -e "\033[31m▶ 系統重啟中...\033[0m"
        shutdown -r now
    fi
}

# 休眠操作
hibernate_system() {
    if check_hibernate_support; then
        echo -e "\n\033[32m✓ 進入休眠模式 (數據將保存到硬盤)\033[0m"
        
        # 5秒倒計時確認
        if countdown 5 "休眠"; then
            systemctl hibernate
        fi
    else
        echo -e "\n\033[31m✗ 錯誤：當前系統不支持休眠功能\033[0m"
        read -p "按 Enter 返回主菜單..."
    fi
}

# 檢查休眠支持
check_hibernate_support() {
    # 檢查內核支持
    if ! grep -q "disk" /sys/power/state 2>/dev/null; then
        return 1
    fi
    
    # 檢查 swap 空間
    local swap_size=$(free -b | awk '/Swap/{print $2}')
    local mem_size=$(free -b | awk '/Mem/{print $2}')
    if [ $swap_size -lt $mem_size ]; then
        return 1
    fi
    
    # 檢查 resume 參數
    if ! grep -q "resume=" /proc/cmdline; then
        return 1
    fi
    
    return 0
}

# 睡眠操作
suspend_system() {
    echo -e "\n\033[32m✓ 進入睡眠模式 (數據保留在內存)\033[0m"
    
    # 3秒倒計時確認
    if countdown 3 "睡眠"; then
        systemctl suspend
    fi
}

# 定時操作
schedule_task() {
    local type=$1
    local type_desc=$2
    
    while true; do
        clear
        echo -e "\n\033[36m===== ${type_desc}設置 =====\033[0m"
        echo "1. 按分鐘設置"
        echo "2. 按具體時間設置 (HH:MM)"
        echo "3. 返回主菜單"
        echo -e "\033[36m=======================\033[0m"
        
        read -p "請選擇 [1-3]: " choice
        
        case $choice in
            1)
                read -p "請輸入分鐘數: " minutes
                if [[ "$minutes" =~ ^[0-9]+$ ]]; then
                    shutdown -${type} +${minutes}
                    echo -e "\n\033[32m✓ 已設定在 $minutes 分鐘後${type_desc}\033[0m"
                    
                    # 顯示剩餘時間（秒）
                    local seconds=$((minutes * 60))
                    echo -e "\n\033[33m▶ ${type_desc}倒計時開始...\033[0m"
                    countdown $seconds "${type_desc}"
                    
                    sleep 2
                    return
                else
                    echo -e "\033[31m✗ 無效輸入，請輸入數字\033[0m"
                    sleep 1
                fi
                ;;
            2)
                read -p "請輸入時間 (24小時制，格式 HH:MM): " target_time
                if [[ "$target_time" =~ ^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                    shutdown -${type} ${target_time}
                    echo -e "\n\033[32m✓ 已設定在 ${target_time} ${type_desc}\033[0m"
                    
                    # 計算剩餘時間（秒）
                    local now_sec=$(date +%s)
                    local target_sec=$(date -d "$target_time" +%s)
                    local seconds=$((target_sec - now_sec))
                    
                    if [ $seconds -gt 0 ]; then
                        echo -e "\n\033[33m▶ ${type_desc}倒計時開始...\033[0m"
                        countdown $seconds "${type_desc}"
                    fi
                    
                    sleep 2
                    return
                else
                    echo -e "\033[31m✗ 時間格式無效，請使用 HH:MM 格式\033[0m"
                    sleep 1
                fi
                ;;
            3) return ;;
            *)
                echo -e "\033[31m✗ 無效選項\033[0m"
                sleep 1
                ;;
        esac
    done
}

# 顯示休眠狀態
show_hibernate_status() {
    echo -e "\n\033[34m[休眠狀態]\033[0m"
    
    # 1. 檢查內核支持
    if grep -q "disk" /sys/power/state 2>/dev/null; then
        echo -e "內核支持: \033[32m是\033[0m"
    else
        echo -e "內核支持: \033[31m否\033[0m"
    fi
    
    # 2. 檢查 swap 空間
    local swap_size=$(free -b | awk '/Swap/{print $2}')
    local mem_size=$(free -b | awk '/Mem/{print $2}')
    echo -e "Swap 空間: $(free -h | awk '/Swap/{print $2}')"
    
    if [ $swap_size -ge $mem_size ]; then
        echo -e "Swap 大小: \033[32m充足 (≥ 物理內存)\033[0m"
    else
        echo -e "Swap 大小: \033[31m不足 (< 物理內存)\033[0m"
    fi
    
    # 3. 檢查 resume 參數配置
    local resume_param=$(grep -oP 'resume=\K\S+' /proc/cmdline 2>/dev/null)
    if [ -n "$resume_param" ]; then
        echo -e "resume 參數: \033[32m已設置 ($resume_param)\033[0m"
    else
        echo -e "resume 參數: \033[31m未設置\033[0m"
    fi
    
    # 4. 檢查 initramfs 配置
    if [ -f /etc/initramfs-tools/conf.d/resume ]; then
        local resume_initramfs=$(grep -v '^#' /etc/initramfs-tools/conf.d/resume | xargs)
        if [ -n "$resume_initramfs" ]; then
            echo -e "initramfs 配置: \033[32m已設置 ($resume_initramfs)\033[0m"
        else
            echo -e "initramfs 配置: \033[31m未設置\033[0m"
        fi
    else
        echo -e "initramfs 配置: \033[31m未配置\033[0m"
    fi
    
    # 5. 綜合狀態評估
    if [ -n "$resume_param" ] && [ -n "$resume_initramfs" ] && \
       [ $swap_size -ge $mem_size ] && grep -q "disk" /sys/power/state; then
        echo -e "\n\033[42m綜合狀態: 休眠功能已啟用\033[0m"
        return 0
    else
        echo -e "\n\033[41m綜合狀態: 休眠功能未完全配置\033[0m"
        return 1
    fi
}

# 設置 Resume 參數
setup_resume_param() {
    echo -e "\n\033[34m[配置 Resume 參數]\033[0m"
    
    # 1. 識別 swap 設備
    local swap_device=$(swapon --show=NAME --noheadings | head -n1)
    
    if [ -z "$swap_device" ]; then
        echo -e "\033[31m✗ 未找到 swap 設備，請先創建 swap 空間\033[0m"
        return 1
    fi
    
    # 2. 獲取 swap 設備的 UUID
    local swap_uuid=""
    if [[ $swap_device =~ ^/dev/ ]]; then
        swap_uuid=$(blkid -s UUID -o value $swap_device)
    elif [[ $swap_device =~ ^/swapfile ]]; then
        # 對於 swap 文件，需要獲取其所在分區的 UUID
        local partition=$(df --output=source $swap_device | tail -n1)
        swap_uuid=$(blkid -s UUID -o value $partition)
    fi
    
    if [ -z "$swap_uuid" ]; then
        echo -e "\033[31m✗ 無法獲取 swap 設備的 UUID\033[0m"
        return 1
    fi
    
    echo -e "檢測到 swap 設備: $swap_device (UUID: $swap_uuid)"
    
    # 3. 配置 GRUB
    echo -e "配置 GRUB 引導參數..."
    local grub_file="/etc/default/grub"
    local resume_param="resume=UUID=$swap_uuid"
    
    # 備份原始文件
    cp "$grub_file" "${grub_file}.bak-$(date +%Y%m%d%H%M%S)"
    
    # 添加或更新 resume 參數
    if grep -q "GRUB_CMDLINE_LINUX_DEFAULT" "$grub_file"; then
        if grep -q "resume=" "$grub_file"; then
            # 更新現有的 resume 參數
            sed -i "s|resume=[^ \"]*|$resume_param|g" "$grub_file"
            echo -e "✓ 已更新 GRUB 中的 resume 參數"
        else
            # 添加新的 resume 參數
            sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"|& $resume_param |" "$grub_file"
            echo -e "✓ 已添加 resume 參數到 GRUB"
        fi
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$resume_param\"" >> "$grub_file"
        echo -e "✓ 已創建新的 GRUB 配置"
    fi
    
    # 4. 配置 initramfs
    echo -e "配置 initramfs..."
    local initramfs_conf="/etc/initramfs-tools/conf.d/resume"
    echo "RESUME=$resume_param" > "$initramfs_conf"
    echo -e "✓ 已設置 initramfs 配置"
    
    # 5. 更新配置
    echo -e "更新系統配置..."
    update-grub
    update-initramfs -u
    
    echo -e "\n\033[42m✓ Resume 參數已成功配置\033[0m"
    echo -e "請重啟系統使更改生效"
    sleep 3
}

# 啟用休眠功能
enable_hibernate() {
    echo -e "\n\033[34m[啟用休眠功能]\033[0m"
    
    # 1. 檢查並設置 resume 參數
    if ! grep -q "resume=" /proc/cmdline; then
        echo -e "檢測到 resume 參數未設置，將自動配置..."
        setup_resume_param
    else
        echo -e "resume 參數已設置，跳過配置"
    fi
    
    # 2. 確保配置生效
    echo -e "更新系統配置..."
    update-grub
    update-initramfs -u
    
    # 3. 啟用 systemd 服務
    systemctl unmask systemd-hibernate.service
    systemctl unmask systemd-hybrid-sleep.service
    
    echo -e "\n\033[42m✓ 休眠功能已成功啟用\033[0m"
    echo -e "請重啟系統使更改生效"
    sleep 3
}

# 禁用休眠功能
disable_hibernate() {
    echo -e "\n\033[34m[禁用休眠功能]\033[0m"
    
    # 1. 移除 GRUB 參數
    local grub_file="/etc/default/grub"
    if [ -f "$grub_file" ]; then
        # 備份原始文件
        cp "$grub_file" "${grub_file}.bak-$(date +%Y%m%d%H%M%S)"
        
        # 移除 resume 參數
        sed -i "s| resume=[^ \"]*||g" "$grub_file"
        update-grub
        echo -e "✓ 已從 GRUB 配置中移除 resume 參數"
    fi
    
    # 2. 移除 initramfs 配置
    local initramfs_conf="/etc/initramfs-tools/conf.d/resume"
    if [ -f "$initramfs_conf" ]; then
        rm -f "$initramfs_conf"
        echo -e "✓ 已移除 initramfs 配置"
    fi
    
    # 3. 更新 initramfs
    update-initramfs -u
    
    # 4. 禁用 systemd 休眠
    systemctl mask systemd-hibernate.service
    systemctl mask systemd-hybrid-sleep.service
    
    echo -e "\n\033[42m✓ 休眠功能已禁用\033[0m"
    echo -e "請重啟系統使更改生效"
    sleep 3
}

# 創建 swap 文件
create_swap_file() {
    echo -e "\n\033[34m[創建 swap 文件]\033[0m"
    
    # 1. 確定內存大小
    local mem_size=$(free -m | awk '/Mem/{print $2}')
    local swap_size=$((mem_size * 2))  # 推薦為內存的2倍
    
    echo -e "檢測到系統內存: ${mem_size}MB"
    echo -e "推薦 swap 大小: ${swap_size}MB"
    
    # 2. 獲取用戶輸入
    read -p "請輸入 swap 文件大小 (MB) [默認: ${swap_size}]: " custom_size
    if [[ -n "$custom_size" && "$custom_size" =~ ^[0-9]+$ ]]; then
        swap_size=$custom_size
    fi
    
    # 3. 選擇 swap 文件位置
    local swap_path="/swapfile"
    read -p "請輸入 swap 文件路徑 [默認: ${swap_path}]: " custom_path
    if [ -n "$custom_path" ]; then
        swap_path="$custom_path"
    fi
    
    # 4. 檢查磁盤空間
    local available_space=$(df -m --output=avail "$(dirname "$swap_path")" | tail -n1)
    if [ "$available_space" -lt "$swap_size" ]; then
        echo -e "\033[31m✗ 磁盤空間不足 (可用: ${available_space}MB < 需求: ${swap_size}MB)\033[0m"
        sleep 2
        return 1
    fi
    
    # 5. 創建 swap 文件
    echo -e "\n創建 ${swap_size}MB swap 文件: $swap_path"
    fallocate -l ${swap_size}M "$swap_path"
    chmod 600 "$swap_path"
    mkswap "$swap_path"
    swapon "$swap_path"
    
    # 6. 永久配置
    echo -e "\n配置永久掛載..."
    if ! grep -q "$swap_path" /etc/fstab; then
        echo "$swap_path none swap sw 0 0" >> /etc/fstab
        echo -e "✓ 已添加到 /etc/fstab"
    else
        echo -e "✓ 已在 /etc/fstab 中存在"
    fi
    
    # 7. 自動配置 resume 參數
    read -p "是否自動配置 resume 參數？ [Y/n] " configure_resume
    if [[ ! $configure_resume =~ ^[Nn]$ ]]; then
        setup_resume_param
    fi
    
    # 8. 驗證
    echo -e "\n\033[32m✓ swap 文件已創建並啟用\033[0m"
    echo -e "當前 swap 狀態:"
    swapon --show
    sleep 3
}

# 電源管理菜單
power_menu() {
    while true; do
        clear
        echo -e "\033[44m===========================================\033[0m"
        echo -e "\033[44m            電源操作菜單                  \033[0m"
        echo -e "\033[44m===========================================\033[0m"
        
        show_system_info
        show_scheduled_tasks
        
        echo -e "\n\033[1m操作選項:\033[0m"
        echo " 1. 立即關機"
        echo " 2. 立即重啟"
        echo " 3. 休眠系統 (Hibernate)"
        echo " 4. 睡眠模式 (Suspend)"
        echo " 5. 定時關機"
        echo " 6. 定時重啟"
        echo " 7. 取消預定任務"
        echo " 8. 返回主菜單"
        echo -e "\033[44m===========================================\033[0m"
        
        read -p "請選擇操作 [1-8]: " choice
        
        case $choice in
            1) power_off 10 ;;  # 10秒延遲關機
            2) reboot_system 10 ;;  # 10秒延遲重啟
            3) hibernate_system ;;
            4) suspend_system ;;
            5) schedule_task "h" "關機" ;;
            6) schedule_task "r" "重啟" ;;
            7) cancel_scheduled ;;
            8) return ;;
            *)
                echo -e "\n\033[31m✗ 無效選擇，請重新輸入\033[0m"
                sleep 2
                ;;
        esac
    done
}

# 休眠管理菜單
hibernate_menu() {
    while true; do
        clear
        echo -e "\033[44m===========================================\033[0m"
        echo -e "\033[44m            休眠管理菜單                  \033[0m"
        echo -e "\033[44m===========================================\033[0m"
        
        show_hibernate_status
        
        echo -e "\n\033[1m操作選項:\033[0m"
        echo " 1. 啟用休眠功能"
        echo " 2. 禁用休眠功能"
        echo " 3. 創建 swap 文件"
        echo " 4. 設置 resume 參數"
        echo " 5. 查看詳細配置"
        echo " 6. 返回主菜單"
        echo -e "\033[44m===========================================\033[0m"
        
        read -p "請選擇操作 [1-6]: " choice
        
        case $choice in
            1) enable_hibernate ;;
            2) disable_hibernate ;;
            3) create_swap_file ;;
            4) setup_resume_param ;;
            5)
                echo -e "\n\033[36m[詳細配置信息]\033[0m"
                echo -e "內核休眠支持:"
                cat /sys/power/state 2>/dev/null || echo "無法訪問 /sys/power/state"
                echo -e "\nGRUB 配置:"
                grep "GRUB_CMDLINE_LINUX" /etc/default/grub 2>/dev/null
                echo -e "\ninitramfs 配置:"
                cat /etc/initramfs-tools/conf.d/resume 2>/dev/null
                echo -e "\nSwap 空間:"
                swapon --show
                echo -e "\n/proc/cmdline 內容:"
                cat /proc/cmdline
                read -p "按 Enter 繼續..."
                ;;
            6) return ;;
            *)
                echo -e "\n\033[31m✗ 無效選擇，請重新輸入\033[0m"
                sleep 2
                ;;
        esac
    done
}

# 主菜單
main_menu() {
    while true; do
        clear
        echo -e "\033[44m===========================================\033[0m"
        echo -e "\033[44m          全能電源管理腳本 v4.0            \033[0m"
        echo -e "\033[44m          含Resume參數自動配置             \033[0m"
        echo -e "\033[44m===========================================\033[0m"
        
        show_system_info
        
        echo -e "\n\033[1m主菜單:\033[0m"
        echo " 1. 電源操作 (關機/重啟/休眠)"
        echo " 2. 休眠管理 (啟用/禁用/配置)"
        echo " 3. 查看系統日志"
        echo " 4. 檢查電源狀態"
        echo " 0. 退出腳本"
        echo -e "\033[44m===========================================\033[0m"
        
        read -p "請選擇操作 [0-4]: " choice
        
        case $choice in
            1) power_menu ;;
            2) hibernate_menu ;;
            3) 
                echo -e "\n\033[36m系統日志查看 (最近10條電源相關):\033[0m"
                journalctl -b -p 0..4 -n 10 --no-pager | grep -i 'power\|shutdown\|hibernate\|suspend\|resume'
                read -p "按 Enter 繼續..."
                ;;
            4)
                echo -e "\n\033[36m電源狀態檢測:\033[0m"
                echo -e "電池狀態: $(upower -i $(upower -e | grep BAT) | grep state | awk '{print $2}')"
                echo -e "休眠支持: $(grep -q "deep" /sys/power/mem_sleep && echo "是" || echo "否")"
                echo -e "Swap 空間: $(free -h | awk '/Swap/{print $2}')"
                echo -e "Resume參數: $(grep -o 'resume=[^ ]*' /proc/cmdline || echo '未設置')"
                read -p "按 Enter 繼續..."
                ;;
            0)
                echo -e "\n\033[32m✓ 已退出電源管理腳本\033[0m"
                exit 0
                ;;
            *)
                echo -e "\n\033[31m✗ 無效選擇，請重新輸入\033[0m"
                sleep 2
                ;;
        esac
    done
}

# 腳本入口
check_root
main_menu