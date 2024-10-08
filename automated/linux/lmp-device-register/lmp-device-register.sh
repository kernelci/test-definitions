#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2022 Foundries.io Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
TOKEN=""
REG_UUID=""
HSM_MODULE="/usr/lib/softhsm/libsofthsm2.so"

usage() {
    echo "Usage: $0 [-s <true|false>]" 1>&2
    exit 1
}

while getopts "s:t:u:m:" o; do
  case "$o" in
    s) SKIP_INSTALL="${OPTARG}" ;;
    t) TOKEN="${OPTARG}" ;;
    u) REG_UUID="${OPTARG}" ;;
    m) HSM_MODULE="${OPTARG}" ;;
    *) usage ;;
  esac
done

! check_root && error_msg "You need to be root to run this script."
create_out_dir "${OUTPUT}"

if [ "${SKIP_INSTALL}" = "True" ] || [ "${SKIP_INSTALL}" = "true" ]; then
    warn_msg "Dependencies installation skipped."
else
    # same package name for debian and fedora
    pkgs="uuid-runtime python3-toml"
    install_deps "${pkgs}"
fi

# quit if token is not provided
if [ -z "${TOKEN}" ]; then
	if [ -f /etc/lmp-device-register-token ]; then
		TOKEN=$(head -n1 /etc/lmp-device-register-token)
	else
	    # exit the test
    	error_fatal "Token not provided"
	fi
fi

if [ -z "${REG_UUID}" ]; then
    REG_UUID=$(uuidgen)
fi

if [ ! -f "${HSM_MODULE}" ]; then
    error_fatal "HSM module file not available"
fi

# disable reboot
mkdir -p /etc/sota/conf.d
cp z-99-aklite-callback.toml /etc/sota/conf.d/

DEVICE_NAME=$(cat /etc/hostname)

# try to register with wrong token
pipe0_status "lmp-device-register --name ${DEVICE_NAME} -T 123456789 -u ${REG_UUID} -m ${HSM_MODULE} -S 12345678 -P 87654321 2>&1" "tee ${OUTPUT}/registration.log"
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    grep "Provided token value is not valid" "${OUTPUT}/registration.log"
    check_return "lmp-device-register-bad-token"
else
    report_fail "lmp-device-register-bad-token"
fi

# first run, should be successful
lmp-device-register --name "${DEVICE_NAME}" -T "${TOKEN}" -u "${REG_UUID}" -m "${HSM_MODULE}" -S 12345678 -P 87654321
check_return "lmp-device-register"

# check if aklite is running
echo "checking aklite status"
systemctl --no-pager status aktualizr-lite
check_return "aktualizr-lite-running"

# check if fioconfig is running
echo "checking fioconfig status"
systemctl --no-pager status fioconfig
check_return "fioconfig-running"

# check if all required files are present
ls -l /var/sota/
if [ -f /var/sota/sql.db ]; then
    report_pass "sqldb-present"
else
    report_fail "sqldb-present"
fi

if [ -f /var/sota/sota.toml ]; then
    report_pass "sotatoml-present"
	./check_toml.py --toml-file /var/sota/sota.toml
	check_return "sotatoml-parse"
else
    report_fail "sotatom-present"
	report_skip "sotatoml-parse"
fi

# try to register again
# attempt should fail with proper error message
pipe0_status "lmp-device-register --name ${DEVICE_NAME} -T ${TOKEN} -u ${REG_UUID} -m ${HSM_MODULE} -S 12345678 -P 87654321 2>&1" "tee ${OUTPUT}/registration.log"
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    grep "HSM incorrectly configured" "${OUTPUT}/registration.log"
    check_return "lmp-device-registered-already"
else
    report_fail "lmp-device-registered-already"
fi
