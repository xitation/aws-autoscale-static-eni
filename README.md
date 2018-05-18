
# aws_ec2_eni_attach

The original script was taken from here https://gist.github.com/amontalban/cb5744f8fe9e5ba966fece68dd2b16cb and modified for my own use.

This repo holds scripts to automatically attach a static ip ENI interface to an EC2 host and manage the routing to allow 2 NICs to function correctly.

It’s purpose is for use with an AWS EC2 host that is part of an AWS Autoscale group where only 1 host is added, to allow for AZ failover redundancy.
It allows this host to obtain a deterministic IP's for use in firewall rules, snmp ACLs and other reasons, while letting AWS manage availability.

Note that this script is used in place of dhcpclient to configure routing on eth1.

This script is setup to route all snmp get udp/161 queries out the static ENI interface, you can easly change the ports in the script to suit you.

* The script will automatically attach the eni id, based on the AZ the host is in.
* Then it will add a second routing table called static_eni, route table number 11 defined in /etc/iprouter2/rt_table.
* Then it adds appropriate routes into this new table to prevent asymmetric routing on the new eth1 interface.
* Iptables is configured to mark packets that have a destination port of udp/161 with id 0x1.
* ip route rules are added to specify any packet with marking 0x1 are to route out via the static_eni route table.
* Nat is enabled on eth1 to allow the src ip to be re-written.
* Reverse path route protection is adjusted to allow the packets to return and not be dropped by the kernel.

Before running ensure you edit the ./check-az.sh file and change the ENI_ID’s that are in each AZ to match the ones you provisioned with static IP’s.

./check-az.sh determines the AZ you are in and then runs the ./attach-eni.sh with the correct ENI ID based on the AZ you are currently located in.

./attach-eni.sh is the script with all the logic in it to attach the correct ENI, adjust routing and iptables polices.
You should be able to run this many times without duplicating iptables and route polices.

Run ./install.sh to install scripts, setup routing tables, systemctl params and setup an onboot systemd service

Note that after doing this, all outbound udp/161 traffic will route out via eth1.

Inbound traffic via eth1 will also work correctly.

After install this configuration will persist after a re-boot using a systemd service called static_eni.service.
Kind Regards,


The following IAM role and policy needs to be applied to the EC2 host in order for this to work:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DetachNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:AttachNetworkInterface"
            ],
            "Resource": "*",
            "Condition": {
                "StringEqualsIgnoreCaseIfExists": {
                    "aws:TagKeys/EC2_Manage_ENI": "True"
                }
            }
        }
    ]
}
```

For the policy to apply to your EC2 host a tag of “EC2_Manage_ENI": "True" needs to be added to the EC2 host.
