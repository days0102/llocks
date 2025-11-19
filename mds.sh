#!/bin/bash
###
 # @Author: Outsider
 # @Date: 2025-11-09 18:40:03
 # @LastEditors: Outsider
 # @LastEditTime: 2025-11-19 15:32:48
 # @Description: In User Settings Edit
 # @FilePath: /llocks/client/lock/mds.sh
###

# Configuration
LOG_FILE="/home/lwz/mds_trace.txt"
PID_FILE="/tmp/mds_monitor.pid"
SLEEP_INTERVAL=1

# Lustre Configuration
config_lustre() {
    # Check number of arguments (expecting 5 config parameters)
    if [ "$#" -ne 6 ]; then
        echo "Usage: $0 config <lock_reclaim_pol> <lock_reclaim_batch> <lock_reclaim_batch_per> <lock_limit_mb> <lock_reclaim_threshold_mb> <debug>"
        return 1
    fi

    local lock_reclaim_pol="$1"
    local lock_reclaim_batch="$2"
    local lock_reclaim_batch_per="$3"
    local lock_limit_mb="$4"
    local lock_reclaim_threshold_mb="$5"
    local debug="$6"

    echo "### MDS: Applying Lustre Lock Reclaim Configuration ###"
    echo "  lock_reclaim_pol: $lock_reclaim_pol"
    echo "  ldlm.lock_reclaim_batch: $lock_reclaim_batch"
    echo "  ldlm.lock_reclaim_batch_per: $lock_reclaim_batch_per"
    echo "  ldlm.lock_limit_mb: $lock_limit_mb"
    echo "  ldlm.lock_reclaim_threshold_mb: $lock_reclaim_threshold_mb"

    # 1. Set lock_reclaim_pol
    echo "### MDS -> Setting /sys/fs/lustre/ldlm/lock_reclaim_pol ###"
    echo "$lock_reclaim_pol" | sudo tee /sys/fs/lustre/ldlm/lock_reclaim_pol

    # 2. Set lock_reclaim_batch
    echo "### MDS -> Setting ldlm.lock_reclaim_batch ###"
    sudo lctl set_param ldlm.lock_reclaim_batch=$lock_reclaim_batch

    # 3. Set lock_reclaim_batch_per
    echo "### MDS -> Setting ldlm.lock_reclaim_batch_per ###"
    sudo lctl set_param ldlm.lock_reclaim_batch_per=$lock_reclaim_batch_per

    # 4. Set lock_reclaim_threshold_mb to 0
    echo "### MDS -> Setting ldlm.lock_reclaim_threshold_mb to 0 ###"
    sudo lctl set_param ldlm.lock_reclaim_threshold_mb=0

    # 5. Set lock_limit_mb
    echo "### MDS -> Setting ldlm.lock_limit_mb ###"
    sudo lctl set_param ldlm.lock_limit_mb=$lock_limit_mb

    # 6. Set lock_reclaim_threshold_mb
    echo "### MDS -> Setting ldlm.lock_reclaim_threshold_mb ###"
    sudo lctl set_param ldlm.lock_reclaim_threshold_mb=$lock_reclaim_threshold_mb

    # 7. Clear system caches
    echo "### MDS -> Clearing system caches (drop_caches) ###"
    echo 3 | sudo tee /proc/sys/vm/drop_caches

    # Clear lock statistics
    echo "### MDS -> Setting ldlm.services.ldlm_canceld.stats=clear ###"
    sudo lctl set_param ldlm.services.ldlm_canceld.stats=clear

    # For bebug
    if [ "$debug" -eq 1 ]; then
        echo "### MDS -> Setting debug=dlmtrace ###"
        sudo lctl set_param debug=dlmtrace
        echo "### MDS -> Setting subsystem_debug=ldlm ###"
        sudo lctl set_param subsystem_debug=ldlm
        echo "### MDS -> Setting debug_mb=20 ###"
        sudo lctl set_param debug_mb=20
    else
        echo "### MDS -> Setting debug=0 ###"
        sudo lctl set_param debug=0 2>/dev/null 
    fi
    echo "### MDS -> lctl clear ###"
    sudo lctl clear 2>/dev/null

    echo "### Lustre Lock Reclaim Configuration Complete ###"
}

# Monitoring Loop
monitor_loop() {
    while true; do
        ts=$(date +%s)
        val1=$(sudo lctl get_param -n ldlm.lock_granted_count 2>/dev/null)
        val2=$(sudo lctl get_param -n ldlm.services.ldlm_canceld.stats 2>/dev/null | awk '/ldlm_cancel/ {print $2}')
        state=$(sudo lctl get_param -n ldlm.namespaces.*mdt*.pool.state 2>/dev/null)

        slv=$(echo "$state" | awk '/^  SLV:/ {print $2}')
        clv=$(echo "$state" | awk '/^  CLV:/ {print $2}')
        gsp=$(echo "$state" | awk '/^  GSP:/ {print $2}')
        gp=$(echo "$state" | awk '/^  GP:/ {print $2}')
        gr=$(echo "$state" | awk '/^  GR:/ {print $2}')
        cr=$(echo "$state" | awk '/^  CR:/ {print $2}')
        gs=$(echo "$state" | awk '/^  GS:/ {print $2}')
        g=$(echo "$state" | awk '/^  G:/ {print $2}')
        l=$(echo "$state" | awk '/^  L:/ {print $2}')

        echo "$ts $val1 $val2 $slv $clv $gsp $gp $gr $cr $gs $g $l" >> "$LOG_FILE"
        sleep $SLEEP_INTERVAL
    done
}

# Monitoring Control
monitor_control() {
    if [ "$1" == "start" ]; then
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "### MDS: Lustre Monitor is already running (PID: $(cat "$PID_FILE")) ###"
            return 1
        fi
        
        echo "### Start Lustre Monitoring ###"
         # Create log file header
        echo "timestamp lock_granted lock_cancel pool_slv pool_clv pool_grant_step pool_grante_plan pool_grant_rate pool_cancel_rate pool_grant_speed pool_granted pool_lock" > "$LOG_FILE"

        monitor_loop >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "### MDS: Process PID: $! ###"
        return 0
    elif [ "$1" == "stop" ]; then
        if [ ! -f "$PID_FILE" ]; then
            echo "### MDS: PID file ($PID_FILE) not found. Monitor is not running. ###"
            return 1
        fi
        
        PID=$(cat "$PID_FILE")
        echo "### MDS: Stopping Lustre Monitor (PID: $PID)... ###"
        kill -SIGTERM $PID 2>/dev/null

        # Clean up debug settings
        sudo lctl set_param debug=0 2>/dev/null
        sudo lctl clear 2>/dev/null
        
        rm -f "$PID_FILE"
        echo "### MDS: Stop complete. ###"
    else
        echo "### MDS: Usage: $0 monitor {start|stop} ###"
        return 1
    fi
}

COMMAND="$1"
shift # Remove the first argument (config or monitor)

case "$COMMAND" in
    config)
        config_lustre "$@"
        ;;
    monitor)
        monitor_control "$@"
        ;;
    *)
        echo "### MDS: Usage: $0 {config|monitor} ###"
        exit 1
esac