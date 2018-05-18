#!/bin/bash

# Are we root?
# -----------------------------------------------------
if (( EUID != 0 )); then
   echo "You must be root to do this." 1>&2
   exit 100
fi

# Install missing deps
# -----------------------------------------------------
echo "Checking for missing dependancies, and install if missing..."
if ! rpm -qa | grep -qw epel-release; then
    echo "Installing epel-release as it's not installed"
    yum install epel-release
    #yum-config-manager --enable epel
fi

if ! rpm -qa | grep -qw jq; then
    echo "Installing jq as it's not installed..."
    yum install --enablerepo=epel oniguruma
    yum install --enablerepo=epel jq
fi

if ! rpm -qa | grep -qw unzip; then
    echo "Installing unzip as it's not installed..."
    yum install unzip
fi

echo " up to this bit"

if [ ! -e /usr/local/aws/bin ]; then
    echo "Installing AWS CLI tools..."
    curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
    unzip awscli-bundle.zip
    ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
    aws --version
fi

# Copy scripts and config
# -----------------------------------------------------
echo "Setting up scripts and config..."

# Set eth0 as default dev
echo "Setting eth0 as the default gateway device in /etc/sysconfig/network..."
grep -qF 'GATEWAYDEV=eth0' /etc/sysconfig/network || echo 'GATEWAYDEV=eth0' >> /etc/sysconfig/network

# Add static route table to /etc/iproute2/rt_table
echo "Adding a new route table number 11, name static_eni into /etc/iproute2/rt_tables..."
grep -qF '11      static_eni' /etc/iproute2/rt_tables || echo '11      static_eni' >> /etc/iproute2/rt_tables

# Setup sysctl params
echo "Setting route and ip forward sysctl params..."
echo "net.ipv4.conf.default.rp_filter = 2" > /etc/sysctl.d/01-router.conf
echo "net.ipv4.conf.all.rp_filter = 2" >> /etc/sysctl.d/01-router.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/01-router.conf
sysctl -p /etc/sysctl.d/01-router.conf

# Copy files to locations
echo "Seting up scripts and services..."
cp -v ./check-aws-az.sh /usr/local/bin/
cp -v ./attach-eni.sh /usr/local/bin/
cp -v ./static-eni.service /etc/systemd/system/

# Enable service
echo "Enable static-eni systemd service..."
systemctl enable static-eni
