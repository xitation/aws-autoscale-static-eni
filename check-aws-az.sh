#!/bin/bash

# This script assigns Elastic Network Interface (ENI) passed as argument to current instance.
# The goal of this script is to attach an ENI to a single instance running in an ASG for example.

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/root/bin

PROG_NAME=$(basename $0)
CURL=$(which curl)
ADDENI="/usr/local/bin/attach-eni.sh"
AZA_ENI_ID="eni-********"
AZB_ENI_ID="eni-********"

export http_proxy="";
export https_proxy="";
export ftp_proxy="";
export no_proxy="localhost, 169.254.169.254";
export HTTP_PROXY="";
export HTTPS_PROXY="";
export FTP_PROXY="";
export NO_PROXY="localhost, 169.254.169.254";

# Are we root?
# -----------------------------------------------------
if (( EUID != 0 )); then
   echo "You must be root to do this." 1>&2
   exit 100
fi

get_az_info () {
    AZ=$(${CURL} -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
}

main() {
INSTANCE_ID=$(${CURL} -s http://169.254.169.254/latest/meta-data/instance-id)

echo "Checking which AZ we are in..."
echo "Debug ${AZ}"
echo "Debug $AZA_ENI_ID"
echo "Debug $AZB_ENI_ID"
if [ "${AZ}" == "ap-southeast-2a" ]; then
    echo "Currently in ${AZ}, Attaching local $AZA_ENI_ID to $INSTANCE_ID"
    sudo ${ADDENI} $AZA_ENI_ID
    else
        if [ "${AZ}" == "ap-southeast-2b" ]; then
            echo "Currently in ${AZ}, Attaching local $AZB_ENI_ID to $INSTANCE_ID"
            sudo ${ADDENI} $AZB_ENI_ID
        else
            echo "Not in supported AZ exiting"
            exit 0
        fi
fi
}

get_az_info $@
main

exit 0
