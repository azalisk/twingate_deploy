#!/bin/bash

REGION="us-west-1"
AMI="ami-0121ef35996ede438"

if [[ ! -f .aws/credentials ]]
	then
		echo "use 'aws config'"
fi

echo "creating vpc"
VPC_ID=$(aws ec2 create-vpc --cidr-block 192.168.0.0/16 --query 'Vpc.{VpcId:VpcId}' --output text --region $REGION)
aws ec2 create-tags --resources $VPC_ID --tags "Key=Name,Value='my_vpc'" --region $REGION
echo ""

echo "creating subnet"
SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.1.0/24 --availability-zone us-west-1a --query 'Subnet.{SubnetId:SubnetId}' --output text --region $REGION)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
aws ec2 create-tags --resources $SUBNET_ID --tags "Key=Name,Value='192.168.1.0 - us-west-1a'" --region $REGION
echo""

echo "creating group"
GROUP_ID=$(aws ec2 create-security-group --group-name "TwinGate" --description "twingate group" --vpc-id $VPC_ID --output text --region $REGION)
aws ec2 authorize-security-group-ingress --group-id $GROUP_ID --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=0.0.0.0/0,Description="SSH in"}]' IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0,Description="HTTP in"}]'
aws ec2 create-tags --resources $GROUP_ID --tags "Key=Name,Value='TwinGate group'" --region $REGION
echo ""

echo "creating keys"
aws ec2 create-key-pair --key-name twinkey --query 'KeyMaterial' --output text > ~/twinkey.pem
chmod 400 ~/twinkey.pem
echo ""

echo "creating gateway"
GW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' --output text --region $REGION)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway $GW_ID --region $REGION
aws ec2 create-tags --resources $GW_ID --tags "Key=Name,Value='Gateway'" --region $REGION
echo ""

echo "creating routes"
RW_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.{RouteTableId:RouteTableId}' --output text --region $REGION)
aws ec2 create-tags --resources $RW_ID --tags "Key=Name,Value='RT'" --region $REGION
aws ec2 create-route --route-table-id $RW_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $GW_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUBNET_ID --route-table-id $RW_ID --region $REGION
echo ""

echo "creating ec2"
INSTANCE_ID=$(aws ec2 run-instances --image-id $AMI --count 1 --instance-type t2.micro --key-name twinkey --security-group-ids $GROUP_ID --subnet-id $SUBNET_ID --query 'Instances[].InstanceId' --output text --region $REGION)
aws ec2 wait instance-running --instance-ids $INSTANCE_ID
aws ec2 create-tags --resources $INSTANCE_ID --tags "Key=Name,Value='EC2'" --region $REGION
echo ""

echo "installing nginx"
IP=$(aws ec2 describe-instances --instance-id i-0f7a1f70a9caa914e --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
ssh -i ~/twinkey.pem -o "StrictHostKeyChecking no" -u ubuntu $IP -c

#aws ec2 terminate-instances --instance-ids $INSTANCE_ID
#sleep 30
#aws ec2 delete-key-pair --key-name twinkey
#aws ec2 delete-security-group --group-id $GROUP_ID
#aws ec2 delete-subnet --subnet-id $SUBNET_ID
#aws ec2 delete-vpc --vpc-id $VPC_ID
