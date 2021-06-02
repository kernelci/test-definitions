#!/bin/bash

. ../../lib/sh-test-lib

start_test() {
	echo "=============================================="
	echo "$1"
	echo "=============================================="
	dmesg_capture_start
}

run_tests() {
	UDELAY_PATH=/sys/kernel/debug/udelay_test
	FREQUENCY=$1
	readarray -t INTERVALS < <(seq 1 1 119; seq 200 10 499; seq 500 100 2000)
	for INTERVAL in "${INTERVALS[@]}"; do
		TEST="udelay(${INTERVAL})@${FREQUENCY}"
		echo ${INTERVAL} 100 > ${UDELAY_PATH}
		RESULTS=$(cat ${UDELAY_PATH})
		if [[ $RESULTS =~ "FAIL" ]]; then
			report_fail $TEST
		else
			report_pass $TEST
		fi
	done
}

OUTPUT="$(pwd)/output"
mkdir -p "${OUTPUT}"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE

! check_root && error_msg "This script must be run as root"
create_out_dir "${OUTPUT}"

# Test to ensure that udelay() delays at least as long as requested as compared to ktime().
# Test a variety of delays at mininmum and maximum cpu frequencies.

start_test "Test udelay() via the test_udelay module"
modprobe test_udelay 2> "$OUTPUT_DIR/test_udelay.err"
RET=$?
cat "$OUTPUT_DIR/test_udelay.err"
if [ $RET -ne 0 ];then
	echo "Error: unable to probe kernel module test_udelay"
fi

read -a AVAILABLE_GOVERNORS <<< $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors)
read -a AVAILABLE_FREQUENCIES <<< $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)

readarray -t GOVERNORS < <(find /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor)
readarray -t SETSPEEDS < <(find /sys/devices/system/cpu/cpu*/cpufreq/scaling_setspeed)
readarray -t CUR_FREQS < <(find /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_cur_freq)

if [[ ! "${AVAILABLE_GOVERNORS[@]}" =~ "userspace" ]]; then
	echo NO USERSPACE GOVERNORS
	run_tests "<unknown_freq>"
else
	# switch to 'userspace' governor
	readarray -t INITIAL_GOVERNORS < <(cat "${GOVERNORS[@]}")
	for GOVERNOR in "${GOVERNORS[@]}"; do
		echo userspace > ${GOVERNOR}
	done

	for FREQUENCY in "${AVAILABLE_FREQUENCIES[@]}"; do
		for SETSPEED in "${SETSPEEDS[@]}"; do
			echo ${FREQUENCY} > ${SETSPEED}
		done
		run_tests ${FREQUENCY}KHz
	done

	# restore initial governors
	for (( i=0; i<${#INITIAL_GOVERNORS[*]}; i++ )); do
    	echo "${INITIAL_GOVERNORS[$i]}" > "${GOVERNORS[$i]}"
	done
fi
