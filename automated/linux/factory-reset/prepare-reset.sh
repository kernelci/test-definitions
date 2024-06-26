#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2022 Foundries.io Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
export RESULT_FILE
TYPE="factory_reset"
ADDITIONAL_TYPE=""
LABEL=""
SOTA_DIR="/etc/sota"
SOTA_CONFDIR="${SOTA_DIR}/conf.d"
HSM_MODULE=""

usage() {
    echo "\
    Usage: $0 [-t <factory_reset|factory_reset_keep_sota|factory_reset_keep_sota_docker>]
              [-a <factory_reset|factory_reset_keep_sota|factory_reset_keep_sota_docker>]
              [-l <target label>]
              [-S <hsm module>]

    -t <factory_reset|factory_reset_keep_sota|factory_reset_keep_sota_docker>
        factory_reset: Full reset, removes contents of /etc/ and /var/
        factory_reset_keep_sota: Keeps /var/sota without changes
        factory_reset_keep_sota_docker: Keeps /var/sota and /var/lib without changes
    -a <factory_reset|factory_reset_keep_sota|factory_reset_keep_sota_docker>
        same as -t. Allows to create 2 files and test the priority order
    -l <target label>
        Adds a label/tag to the [pacman] section of the toml. This forces aktualizr-lite
        to use the tag and avoids possible unintentional OTA update.
    -S <hsm module>
        Enables factory registration with HSM module. This option assumes using
        pkcs#11 database. Works with FoundriesFactory. Requires support in
        FoundriesFactory auto registration script.
    "
}

while getopts "t:a:l:S:h" opts; do
    case "$opts" in
        t) TYPE="${OPTARG}";;
        a) ADDITIONAL_TYPE="${OPTARG}";;
        l) LABEL="${OPTARG}";;
        S) HSM_MODULE="${OPTARG}";;
        h|*) usage ; exit 1 ;;
    esac
done

# the script works only on builds with aktualizr-lite
# and lmp-device-auto-register

! check_root && error_msg "You need to be root to run this script."
create_out_dir "${OUTPUT}"

# configure aklite callback
cp aklite-callback.sh /var/sota/
chmod 755 /var/sota/aklite-callback.sh

mkdir -p "${SOTA_CONFDIR}"
cp z-99-aklite-callback.toml "${SOTA_CONFDIR}"
cp z-99-aklite-disable-reboot.toml "${SOTA_CONFDIR}"
if [ -n "${LABEL}" ]; then
    # tag will be applied to aklite settings
    # from auto-registration script
    echo "${LABEL}" > "${SOTA_DIR}/tag"
fi
if [ -n "${HSM_MODULE}" ]; then
    echo "HSM_MODULE=\"${HSM_MODULE}\"" > /etc/sota/hsm
    echo "HSM_PIN=87654321" >> /etc/sota/hsm
    echo "HSM_SOPIN=12345678" >> /etc/sota/hsm
fi
# create signal files
touch /var/sota/ota.signal
touch /var/sota/ota.result

#systemctl mask aktualizr-lite
# enabling lmp-device-auto-register will fail because aklite is masked
systemctl enable --now lmp-device-auto-register || error_fatal "Unable to register device"

while ! systemctl is-active aktualizr-lite; do
    echo "Waiting for aktualizr-lite to start"
    sleep 1
done

while ! journalctl --no-pager -u aktualizr-lite | grep "Device is up-to-date"; do
    echo "Waiting for aktualizr-lite to complete initialization"
    sleep 1
done

ls -l /etc/sota
ls -l /var/sota

if [ -f /etc/sota/conf.d/z-99-aklite-callback.toml ]; then
    report_pass "${TYPE}-aklite-callback-created"
else
    report_fail "${TYPE}-aklite-callback-created"
fi

if [ -f /var/sota/sql.db ]; then
    report_pass "${TYPE}-device-registration"
else
    report_fail "${TYPE}-device-registration"
fi
if [ -n "${HSM_MODULE}" ]; then
    if grep "${HSM_MODULE}" /var/sota/sota.toml; then
        report_pass "${TYPE}-hsm-registration"
    else
        report_fail "${TYPE}-hsm-registration"
    fi
else
    report_skip "${TYPE}-hsm-registration"
fi

touch "/var/.${TYPE}"
if [ -n "${ADDITIONAL_TYPE}" ]; then
    touch "/var/.${ADDITIONAL_TYPE}"
fi
