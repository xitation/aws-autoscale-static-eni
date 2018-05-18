#!/usr/bin/env bash

# This script assigns Elastic Network Interface (ENI) passed as argument to current instance.
# The goal of this script is to attach an ENI to a single instance running in an ASG for example.

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/root/bin

# Varaibles
PROG_NAME=$(basename $0)
AWSCLI=$(which aws)
JQ=$(which jq)
CURL=$(which curl)
TR=$(which tr)
DHCLIENT=$(which dhclient)
IFCONFIG=$(which ifconfig)
GREP=$(which grep)
CUT=$(which cut)
AWK=$(which awk)
SED=$(which sed)
NIC="eth1"
IP=$(which ip)
REGION=$(${CURL} -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
IPTABLES=$(which iptables)
SYSCTL=$(which sysctl)

export http_proxy="";
export https_proxy="";
export ftp_proxy="";
export no_proxy="localhost, 169.254.169.254";
export HTTP_PROXY="";
export HTTPS_PROXY="";
export FTP_PROXY="";
export NO_PROXY="localhost, 169.254.169.254";

# Request ENI_ID user input peramiter
ENI_ID=$1

# Define usage info
usage() {
    cat<<EOF
NAME
    ${PROG_NAME} -- Assign an Elastic Network Interface to this instance

SYNOPSIS
    ${PROG_NAME} eni-id

EXIT STATUS
     The ${PROG_NAME} utility exits 0 on success, and > 0 if an error occurs.
EOF

    exit 0
}

# Are we root?
# -----------------------------------------------------
if (( EUID != 0 )); then
   echo "You must be root to do this." 1>&2
   exit 100
fi

parse_cmdline() {

# Work out if we show usage or run script based on user paramiter provided or not.
  if [ $# -eq 0 ]; then
    usage
  else
    while [ $# -gt 0 ]; do
      case "$1" in
        -*)
          usage
          ;;
        *)
          break
          ;;
      esac
      shift
    done
  fi
}

get_eni_info () {
    # Function to get ENI info
    # Requires 1 peramiter ENI_ID of the ENI you wish to view
    local ENI_ID=$1

    ${AWSCLI} ec2 describe-network-interfaces --region $REGION --filters Name=network-interface-id,Values=${ENI_ID}
}

attach_eni () {
    # Function to attach ENI to EC2 instance using aws cli tools
    # Requires 2 paramiters, ENI_ID and INSTANCE_ID to attach to.
    local ENI_ID=$1
    local INSTANCE_ID=$2

    ${AWSCLI} ec2 attach-network-interface --region $REGION --network-interface-id ${ENI_ID} --instance-id ${INSTANCE_ID} --device-index 1
}

dettach_eni () {
    # Function to detach ENI using aws cli tools
    # Requires 1 paramiter ENI_ID to detach
    local ENI_ATTACHMENT_ID=$1

    ${AWSCLI} ec2 detach-network-interface --region $REGION --attachment-id ${ENI_ATTACHMENT_ID} --force
}

adjust_route () {
    # Function to handle routing in a new table for second ENI
    # Add static route table to /etc/iproute2/rt_table
    ${GREP} -qF '11      static_eni' /etc/iproute2/rt_tables || echo '11      static_eni' /etc/iproute2/rt_tables

    # Add routes to second route table static_eni defined in /etc/iproute2/rt_table
    if [ "${GATEWAY_ENI}" != ${ENI_IP} ]; then
        echo "Adjusting routing for ${NIC} with ip ${ENI_IP}"
        ${IP} route add default via $GATEWAY dev eth1 tab static_eni
        ${IP} rule add from ${ENI_IP}/32 tab static_eni
        ${IP} rule add to ${ENI_IP}/32 tab static_eni
        ${IP} route flush cache
    fi
}

iptables_config () {
    # Function to apply ip tables, and setup kernel for routing and nat
    if [ "${IPTABLES_CHECK}" != dpt:161 ]; then
        echo "Adding iptables rules for snmp"
        # Setup sysctl params
        echo "net.ipv4.conf.default.rp_filter = 2" > /etc/sysctl.d/01-router.conf
        echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.d/01-router.conf
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/01-router.conf
        ${SYSCTL} -p /etc/sysctl.d/01-router.conf

        # Mangle and mark preroute and output packets when dest port is 161
        ${IPTABLES} -A PREROUTING -t mangle -p udp --dport 161 -j MARK --set-mark 0x1
        ${IPTABLES} -A OUTPUT -t mangle -p udp --dport 161 -j MARK --set-mark 0x1
        # Nat all traffic on $NIC
        ${IPTABLES} -A POSTROUTING -t nat -o ${NIC} -j MASQUERADE

        # Force 0x1 marked packets out static_eni routing table
        ${IP} rule add fwmark 0x1 table static_eni
        ${IP} route flush cache

        # Unset reverse path filtering for all interfaces, or at least for "eth0" and "all"
        for i in /proc/sys/net/ipv4/conf/*/rp_filter; do echo 0 > $i; done
    fi
}

main() {
# Main function which runs all the logic in this script, and calls other functions when conditions are met.

# Populate variables we need later on progromatically
REGION=$(${CURL} -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
ENI_INFO=$(get_eni_info ${ENI_ID})
ENI_IP=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .PrivateIpAddresses[] .PrivateIpAddress' | ${SED} 's/"//g')
ENI_STATUS=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Status' | ${TR} '[A-Z]' '[a-z]' | ${SED} 's/"//g')
INSTANCE_ID=$(${CURL} -s http://169.254.169.254/latest/meta-data/instance-id )
GATEWAY=$(${IP} route | ${AWK} '/default/ { print $3 }')
GATEWAY_ENI=$(${IP} route show table static_eni | ${AWK} '/default/ { print $3 }')
IPTABLES_CHECK=$(${IPTABLES} -nL -v --line-numbers -t mangle | ${AWK} '/[0-9]/ { print $12 }' | ${GREP} -m1 161)

echo "Configuring ENI ${ENI_ID}"
echo "Debug: ${IPTABLES_CHECK}"
if [ "${ENI_STATUS}" == "available" ]; then
    echo "ENI ${ENI_ID} is available, attaching it to ${INSTANCE_ID}"
    while [ "${ENI_STATUS}" == "available" ]; do
        # Attach ENI to current instance
        attach_eni ${ENI_ID} ${INSTANCE_ID}
        ENI_INFO=$(get_eni_info ${ENI_ID})
        ENI_STATUS=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Status' | ${TR} '[A-Z]' '[a-z]' | ${SED} 's/"//g')

        sleep 5
    done
    echo "ENI ${ENI_ID} attached to ${INSTANCE_ID}"
    echo "Configuring ${NIC} with IP ${ENI_IP}"
    # Configure network interface
    ${IFCONFIG} ${NIC} up
    sleep 1
    ${DHCLIENT} ${NIC}
    sleep 1
    adjust_route
    iptables_config
else
    ENI_INSTANCE_ID=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Attachment .InstanceId' | ${SED} 's/"//g')

    if [ "${INSTANCE_ID}" == "${ENI_INSTANCE_ID}" ]; then
        # Check if the IP is configured properly
        NIC_IP=$(${IFCONFIG} ${NIC} | ${GREP} 'inet addr:' | ${CUT} -d: -f2 | ${AWK} '{ print $1}')
        if ! [ "${NIC_IP}" == "${ENI_IP}" ]; then
            echo "Configuring NIC ${NIC}..."
            # Configure network interface
            ${IFCONFIG} ${NIC} up
            sleep 1
            ${DHCLIENT} ${NIC}
            sleep 1
            adjust_route
            iptables_config
        fi
    else
        echo "ENI ${ENI_ID} is attached to ${ENI_INSTANCE_ID}, dettaching..."

        while [ "${ENI_STATUS}" == "in-use" ]; do
            # Dettach ENI
            ENI_ATTACHMENT_ID=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Attachment .AttachmentId' | ${SED} 's/"//g')
            dettach_eni ${ENI_ATTACHMENT_ID}
            ENI_INFO=$(get_eni_info ${ENI_ID})
            ENI_STATUS=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Status' | ${TR} '[A-Z]' '[a-z]' | ${SED} 's/"//g')

            sleep 2
        done

       echo "ENI ${ENI_ID} is available, attaching it to ${INSTANCE_ID}"
        while [ "${ENI_STATUS}" == "available" ]; do
            # Attach ENI to current instance
            attach_eni ${ENI_ID} ${INSTANCE_ID}
            ENI_INFO=$(get_eni_info ${ENI_ID})
            ENI_STATUS=$(echo ${ENI_INFO} | ${JQ} '.NetworkInterfaces[] .Status' | ${TR} '[A-Z]' '[a-z]' | ${SED} 's/"//g')

            sleep 2
        done
        echo "ENI ${ENI_ID} attached to ${INSTANCE_ID}"
        echo "Configuring ${NIC} with IP ${ENI_IP}"
        # Configure network interface
        ${IFCONFIG} ${NIC} up
        sleep 1
        ${DHCLIENT} ${NIC}
        sleep 1
        adjust_route
        iptables_config
    fi
fi
}

parse_cmdline $@
main

exit 0
