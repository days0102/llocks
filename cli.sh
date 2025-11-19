#!/bin/bash
###
 # @Author: Outsider
 # @Date: 2025-11-09 19:06:18
 # @LastEditors: Outsider
 # @LastEditTime: 2025-11-19 15:50:07
 # @Description: In User Settings Edit
 # @FilePath: /llocks/client/lock/cli.sh
### 

# --- A. Global variables and mdtest parameters ---
np=3
item_per_np=10000
test_path=/home/lwz/client/lock

lock_per_mb=2114
mem=1500 

LCTL="sudo lctl"

CLEANUP_DONE=0

MDS_HOST="mds" # MDS hostname
REMOTE_SCRIPT="./mds.sh" # MDS script (config/monitor)

#############################################################
# --- B. Utility functions (copied from lustre test) ---

calc_sum () {
	awk '{sum += $1} END { printf("%0.0f", sum) }'
}

# usage: stack_trap arg sigspec
#
# stack_trap() behaves like bash's built-in trap, except that it "stacks" the
# command "arg" on top of previously defined commands for "sigspec" instead
# of overwriting them.
# stacked traps are executed in reverse order of their registration
#
# arg and sigspec have the same meaning as in man (1) trap
stack_trap()
{
	local arg="$1"
	local sigspec="${2:-EXIT}"

	# Use "trap -p" to get the quoting right
	local old_trap="$(trap -p "$sigspec")"
	# Append ";" and remove the leading "trap -- '" added by "trap -p"
	old_trap="${old_trap:+"; ${old_trap#trap -- \'}"}"

	# Once again, use "trap -p" to get the quoting right
	local new_trap="$(trap -- "$arg" "$sigspec"
			  trap -p "$sigspec"
			  trap -- '' "$sigspec")"

	# Remove the trailing "' $sigspec" part added by "trap -p" and merge
	#
	# The resulting string should be safe to "eval" as it is (supposedly
	# correctly) quoted by "trap -p"
	eval "${new_trap%\' $sigspec}${old_trap:-"' $sigspec"}"
}

# Cancel lru locks across all namespaces containing the given wildcard. If the
# wilcard is omitted, lru locks will be canceled across all namespaces.
# Usage: cancel_lru_locks [namespace_wildcard]
cancel_lru_locks() {
	#$LCTL mark "cancel_lru_locks $1 start"
	sudo lctl set_param -t4 -n "ldlm.namespaces.*$1*.lru_size=clear"
	sudo lctl get_param "ldlm.namespaces.*$1*.lock_unused_count" | grep -v '=0'
	#$LCTL mark "cancel_lru_locks $1 stop"
}

# Print the total of the lock_unused_count across all namespaces containing the
# given wildcard. If the namespace wildcard is omitted, all namespaces will be
# matched.
# Usage: total_unused_locks [namespace_wildcard]
total_unused_locks() {
	sudo lctl get_param -n "ldlm.namespaces.*$1*.lock_unused_count" | calc_sum
}

# Print the total of the lock_count across all namespaces containing the given
# wildcard. If the namespace wilcard is omitted, all namespaces will be matched.
# Usage: total_used_locks [namespace_wildcard]
total_used_locks() {
	sudo lctl get_param -n "ldlm.namespaces.*$1*.lock_count" | calc_sum
}

pool_granted_locks() {
	sudo lctl get_param -n "ldlm.namespaces.*$1*.pool.granted" | calc_sum
}

pool_limit_locks() {
	sudo lctl get_param -n "ldlm.namespaces.*$1*.pool.limit" | calc_sum
}

set_pool_likmit(){
	local dev=${1}
	local limit=${2}
	local old_limit=$(sudo lctl get_param -n "ldlm.namespaces.*$dev*.pool.limit")
	
	sudo lctl set_param "ldlm.namespaces.*$dev*.pool.limit"=$limit

	stack_trap "$LCTL set_param "ldlm.namespaces.*$dev*.pool.limit"=$old_limit || true"
}

default_lru_size()
{
	local nr_cpu=$(grep -c "processor" /proc/cpuinfo)

	echo $((100 * nr_cpu))
}

lru_resize_enable()
{
	$LCTL set_param -n ldlm.namespaces.*$1*.lru_size=0
}

lru_resize_disable()
{
	local dev=${1}
	local lru_size=2000000  #${2:-$(default_lru_size)}
	local size_param="ldlm.namespaces.*$dev*.lru_size"
	local age_param="ldlm.namespaces.*$dev*.lru_max_age"
	local old_age=($($LCTL get_param -n $age_param))
	# can't save/restore lru_size since it reports the *current* lru count

	echo "$size_param=0->$lru_size"
	echo "$age_param=$old_age->3900s"

	# increase lru_max_age also, to prevent lock cancel due to age
	$LCTL set_param -n $size_param=$lru_size
	$LCTL set_param -n $age_param=3900s
	stack_trap "cancel_lru_locks $dev || true"
	stack_trap "lru_resize_enable $dev || true"
	stack_trap "$LCTL set_param -n $age_param=$old_age || true"
}

elc_enable()
{
	$LCTL set_param ldlm.namespaces.*$1*.early_lock_cancel=1
}

elc_disable()
{
	$LCTL set_param ldlm.namespaces.*$1*.early_lock_cancel=0
	stack_trap "elc_enable $1 || true"
}

#################################################################
# --- B. for MDS side ---

# Check MDS script
ssh $MDS_HOST "test -f $REMOTE_SCRIPT"
if [ $? -ne 0 ]; then
    echo "Error: The script $REMOTE_SCRIPT not found on MDS or the permissions are insufficient."
    exit 1
fi

start_mds_monitor() {
    # Call the remote script with 'monitor start' mode (MUST be executed with sudo on MDS)
    ssh $MDS_HOST "$REMOTE_SCRIPT monitor start"
    
    # Check SSH return code
    if [ $? -ne 0 ]; then
        echo "WARN: Remote monitor failed to start! continue."
    fi
    return 0
}

stop_mds_monitor() {
    if [ $CLEANUP_DONE -eq 1 ]; then
        return 0 # Already stopped
    fi

    echo "--- Fin. Stopping Performance Monitor on MDS (via Trap) ---"
    # Call the remote script with 'monitor stop' mode (MUST be executed with sudo on MDS)
    ssh $MDS_HOST "$REMOTE_SCRIPT monitor stop"
    
    if [ $? -ne 0 ]; then
        echo "Warning: Remote monitor failed to stop! Please check MDS manually."
    fi

    CLEANUP_DONE=1
}

#################################
# --- C. for client side ---
start_cli_monitor(){
    monitor_pid_file="/tmp/lock_monitor.pid"
    (
        echo "timestamp ldlm_cancel lock_count lock_unused pool_granted pool_limit pool_slv pool_clv pool_grant_rate pool_cancel_rate pool_grant_speed pool_granted pool_lock" > cli_trace.txt
        while true; do
            ts=$(date +%s)
            val1=$(sudo lctl get_param mdc/*/stats | awk '/^ldlm_cancel/{print $2}')
            val2=$(total_used_locks mdc)
            val3=$(total_unused_locks mdc)
            val4=$(pool_granted_locks mdc)
            val5=$(pool_limit_locks mdc)

            state=$(sudo lctl get_param -n ldlm.namespaces.*mdc*.pool.state)
            slv=$(echo "$state" | awk '/^  SLV:/ {print $2}')
            clv=$(echo "$state" | awk '/^  CLV:/ {print $2}')
            gr=$(echo "$state" | awk '/^  GR:/ {print $2}')
            cr=$(echo "$state" | awk '/^  CR:/ {print $2}')
            gs=$(echo "$state" | awk '/^  GS:/ {print $2}')
            g=$(echo "$state" | awk '/^  G:/ {print $2}')
            l=$(echo "$state" | awk '/^  L:/ {print $2}')

            echo "$ts $val1 $val2 $val3 $val4 $val5 $slv $clv $gr $cr $gs $g $l" >> cli_trace.txt
            sleep 1
        done
    ) &
    monitor_pid=$!
    echo $monitor_pid > "$monitor_pid_file"
}

stop_cli_monitor(){
    echo "--- CLI: Stopping Lustre Monitor (PID: $monitor_pid)... ---"
    kill $monitor_pid 2>/dev/null
    rm -f "$monitor_pid_file"
}

#################################
# --- D. Main Execution Logic ---
cleanup(){
    stop_mds_monitor
    stop_cli_monitor
}
# 1. Set Exit Trap: Ensure stop_monitor is called on exit, Ctrl+C (INT), or TERM signal.
trap cleanup EXIT INT TERM

# caclulate lock limits based on memory size
lock_reclaim_threshold_mb=$(echo "($mem * 0.2)/1" | bc)
lock_limit_mb=$(echo "($mem * 0.3)/1" | bc)

# Ensure item_per_np is calculated based on new lock limits
item_per_np=$(echo "($lock_limit_mb * ($lock_per_mb + $lock_per_mb)) / $np" | bc)

elc=1
debug=0
lru_resize=1
lock_reclaim_pol=1
lock_reclaim_batch=512
lock_reclaim_batch_per=1

echo "================ Testing with mem=${mem}MB ================"
echo "  mem: ${mem}MB"
echo "  np: $np"
echo "  item_per_np: $item_per_np"
echo "  lock_reclaim_threshold_mb: $lock_reclaim_threshold_mb"
echo "  lock_limit_mb: $lock_limit_mb"
echo "  lock_reclaim_threshold: $((lock_reclaim_threshold_mb * lock_per_mb))"
echo "  lock_limit: $((lock_limit_mb * lock_per_mb))"
echo "  lock_reclaim_pol: $lock_reclaim_pol"
echo "  lock_reclaim_batch: $lock_reclaim_batch"
echo "  lock_reclaim_batch_per: $lock_reclaim_batch_per"
echo "  elc: $elc"
echo "  debug: $debug"
echo "  lru_resize: $lru_resize"
echo

# remote configuration on MDS
echo "--- 1. Executing Remote Lustre Global Configuration on MDS ---"
ssh $MDS_HOST "sudo $REMOTE_SCRIPT config \
    \"$lock_reclaim_pol\" \
    \"$lock_reclaim_batch\" \
    \"$lock_reclaim_batch_per\" \
    \"$lock_limit_mb\" \
    \"$lock_reclaim_threshold_mb\" \
    \"$debug\""
if [ $? -ne 0 ]; then
    echo "Error: Remote Lustre Configuration failed! Aborting."
    exit 1 
fi

# local configuration on client
echo "--- 2. Executing Local Lustre Configuration ---"
echo "--- CLI -> cancel_lru_locks mdc osc ---"
cancel_lru_locks mdc
cancel_lru_locks osc
echo "--- CLI -> setting mdc/*/stats=clear ---"
sudo lctl set_param mdc/*/stats=clear

if [ "$lru_resize" -eq 0 ]; then
    echo "--- CLI -> setting lru_resize_disable mdc ---"
    lru_resize_disable mdc
fi

if [ "$elc" -eq 0 ]; then
    echo "--- CLI -> setting elc_disable mdc ---"
    elc_disable mdc
fi

if [ "$debug" -eq 1 ]; then
    echo "--- CLI -> Setting debug=dlmtrace ---"
    sudo lctl set_param debug=dlmtrace
    echo "--- CLI -> Setting subsystem_debug=ldlm ---"
    sudo lctl set_param subsystem_debug=ldlm
    echo "--- CLI -> Setting debug_mb=20 ---"
    sudo lctl set_param debug_mb=20
    echo "--- CLI -> lctl clear ---"
else
    echo "--- CLI -> Setting debug=0 ---"
    sudo lctl set_param debug=0
fi
# Final cleanup before test
sudo lctl clear

# start remote monitoring on MDS
echo "--- 3. Starting Performance Monitor on MDS ---"
start_mds_monitor
if [ $? -ne 0 ]; then
    exit 1 
fi

echo "--- 4. Starting Performance Monitor on CLI ---"
start_cli_monitor

# Run mdtest
echo "--- 5. Running mdtest concurrently with monitoring ---"
mpirun -np $np mdtest -D -T -z 5 -b 5 -n $item_per_np -d $test_path 2>&1 | tee >(tail -n 20 > res_mdtest.txt)
# mpirun -np $np mdtest -D -T -z 5 -b 5 -n $item_per_np -d $test_path 2>&1 | tee >(tail -n 20 >> res_mdtest.txt)
# mpirun -np $np mdtest -D -T -z 5 -b 5 -n $item_per_np -d $test_path 2>&1 | tee >(tail -n 20 >> res_mdtest.txt)

sleep 5 # Wait a moment for any final traces

# finishing up
if [ "$debug" -eq 1 ]; then
    sudo lctl dk > cli_log # Dump local lctl state
    ssh mds "sudo lctl dk > mds_log"
    scp mds:/home/lwz/mds_log mds_log # Copy remote MDS log
fi

scp mds:/home/lwz/mds_trace.txt mds_trace.txt

# The script exits here. The EXIT trap calls stop_monitor to stop remote monitoring.
echo "--- mdtest complete. The monitor will now stop via trap. ---"
