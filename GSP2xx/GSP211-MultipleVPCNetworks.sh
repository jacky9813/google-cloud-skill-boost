#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")

# Leave this variable blank if you want to enable doing all tasks at once
#DISABLE_ALL_TASK=1

splitter(){
    i=$(tput cols)
    while [ $i -gt "0" ]; do
    	echo -n =
        i=$(($i - 1))
    done
}
pause(){
    read -p "Press Enter to continue"
}
check_return(){
    if [ $1 -ne "0" ]; then
        echo "Error detected"
        pause
    fi
}
echo_cmd(){
    splitter
	echo $@
	eval $@
    RET=$?
    if [ $RET -ne "0" ]; then
        echo "Error occured! You can ignore this message and press enter to continue."
        pause
    fi
}
checkpoint(){
    splitter
    echo "Checkpoint reached"
    pause
}

# TODO: PUT THE TASKS HERE
VPC1=managementnet
VPC1_SUBNET_US=managementsubnet-us
VPC2=privatenet
VPC2_SUBNET_US=privatesubnet-us
VPC2_SUBNET_EU=privatesubnet-eu
REGION_US=us-central1
REGION_EU=europe-west4

task1(){
cat << EOF
Task 1 - Create 2 custom mode VPC networks
$(splitter)
In this task, we'll create 2 VPC, 3 subnets, and 2 firewall rules like:
$VPC1
 |- $VPC1_SUBNET_US (subnet, $REGION_US, 10.130.0.0/20)
 |- $VPC1-allow-icmp-ssh-rdp (firewall-rule, INGRESS, priority 1000, ALLOW, from 0.0.0.0/0, tcp:22, tcp:3389, icmp)

$VPC2
 |- $VPC2_SUBNET_US (subnet, $REGION_US, 172.16.0.0/20)
 |- $VPC2_SUBNET_EU (subnet, $REGION_EU, 172.20.0.0/20)
 |- $VPC2-allow-icmp-ssh-rdp (firewall-rule, INGRESS, priority 1000, ALLOW, from 0.0.0.0/0, tcp:22, tcp:3389, icmp)
EOF
pause
echo_cmd gcloud compute networks create $VPC1 --subnet-mode=custom
echo_cmd gcloud compute networks subnets create $VPC1_SUBNET_US --network=$VPC1 --region=$REGION_US --range=10.130.0.0/20
checkpoint

echo_cmd gcloud compute networks create $VPC2 --subnet-mode=custom
echo_cmd gcloud compute networks subnets create $VPC2_SUBNET_US --network=$VPC2 --region=$REGION_US --range=172.16.0.0/20
echo_cmd gcloud compute networks subnets create $VPC2_SUBNET_EU --network=$VPC2 --region=$REGION_EU --range=172.20.0.0/20
checkpoint

echo_cmd gcloud compute networks list
echo_cmd gcloud compute networks subnets list --sort-by=NETWORK

echo_cmd gcloud compute firewall-rules create $VPC1-allow-icmp-ssh-rdp --network=$VPC1 --allow=tcp:22,tcp:3389,icmp --source-ranges=0.0.0.0/0
echo_cmd gcloud compute firewall-rules create $VPC2-allow-icmp-ssh-rdp --direction=INGRESS --priority=1000 --network=$VPC2 --action=ALLOW --rules=icmp,tcp:22,tcp:3389 --source-ranges=0.0.0.0/0
checkpoint

echo_cmd gcloud compute firewall-rules list --sort-by=NETWORK
} # End of task 1

task2(){
cat << EOF
Task 2 - Create VM instances
$(splitter)
In this task, we'll create one instance on each VPC we've created in task 1.
Both instances will be at zone $REGION_US-f, which also means they are limited to use $VPC1-us and $VPC2-us subnets only.
EOF
pause
echo_cmd gcloud compute instances create $VPC1-us-vm --zone=$REGION_US-f --subnet=$VPC1_SUBNET_US --machine-type=f1-micro
checkpoint

echo_cmd gcloud compute instances create $VPC2-us-vm --zone=$REGION_US-f --subnet=$VPC2_SUBNET_US --machine-type=n1-standard-1
checkpoint

echo_cmd gcloud compute instances list --sort-by=ZONE
} # End of task 2

task3(){
VPC1_US_VM_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:$VPC1-us-vm" | tail -n +2)
VPC2_US_VM_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:$VPC2-us-vm" | tail -n +2)
MYNET_EU_VM_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:mynet-eu-vm" | tail -n +2)
VPC1_US_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:$VPC1-us-vm" | tail -n +2)
VPC2_US_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:$VPC2-us-vm" | tail -n +2)
MYNET_EU_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:mynet-eu-vm" | tail -n +2)
cat << EOF
Task 3 - Testing the connectivity between VMs
$(splitter)
In this task, we'll test the connection from mynet-us-vm (VPC: mynetwork) instance to 3 other instances:
    - $VPC1-us-vm (VPC: $VPC1, internal IP: $VPC1_US_VM_INT_IP, external IP: $VPC1_US_VM_EXT_IP)
    - $VPC2-us-vm (VPC: $VPC2, internal IP: $VPC2_US_VM_INT_IP, external IP: $VPC2_US_VM_EXT_IP)
    - mynet-eu-vm (VPC: mynetwork, internal IP: $MYNET_EU_VM_INT_IP, external IP: $MYNET_EU_VM_EXT_IP)

Additionally, we'll also test using both internal IP and external IP as destination.
EOF
pause
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $MYNET_EU_VM_EXT_IP'"
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $VPC1_US_VM_EXT_IP'"
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $VPC2_US_VM_EXT_IP'"
splitter
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $MYNET_EU_VM_INT_IP'"
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $VPC1_US_VM_INT_IP; exit 0'"
echo_cmd "gcloud compute ssh mynet-us-vm --zone=$REGION_US-f --command='ping -c 3 $VPC2_US_VM_INT_IP; exit 0'"
checkpoint
} # End of task 3

task4(){
echo -ne "Preparing task 4...\r"
VM=vm-appliance
VPC1_US_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:$VPC1-us-vm" | tail -n +2)
VPC2_US_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:$VPC2-us-vm" | tail -n +2)
MYNET_EU_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:mynet-eu-vm" | tail -n +2)
MYNET_US_VM_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:mynet-us-vm" | tail -n +2)
cat << EOF
Task 4 - Create VM instance with multiple network interfaces
$(splitter)
In this task, we'll create a VM instance with following specification:

Property        Value
=================================
Name            $VM
Region          $REGION_US
Zone            $REGION_US-f
Machine Type    n1-standard-4
NIC 1 subnet    $VPC2_SUBNET_US
NIC 2 subnet    $VPC1_SUBNET_US
NIC 3 subnet    mynetwork

After the VM instance creation, we'll do:
    - Output the network interfaces information.
    - Test the connectivity to $VPC1-us-vm, $VPC2-us-vm, mynet-us-vm, mynet-eu-vm.

EOF
pause
echo_cmd gcloud compute instances create $VM --zone=$REGION_US-f --machine-type=n1-standard-4 --network-interface=network=$VPC2,subnet=$VPC2_SUBNET_US --network-interface=network=$VPC1,subnet=$VPC1_SUBNET_US --network-interface=network=mynetwork,subnet=mynetwork
checkpoint

echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='sudo ifconfig'"
echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ping -c 3 $VPC2_US_VM_INT_IP'"
echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ping -c 3 $VPC2-us-vm'"
echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ping -c 3 $VPC1_US_VM_INT_IP'"
echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ping -c 3 $MYNET_US_VM_INT_IP'"
echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ping -c 3 $MYNET_EU_VM_INT_IP'"

echo_cmd "gcloud compute ssh $VM --zone=$REGION_US-f --command='ip route'"
} # End of task 4

case "$1" in
    "all")
    	if [ $DISABLE_ALL_TASK ] ; then
    		echo "Doing all tasks at once has been disabled"
    		exit 1
    	else
            if [ "$PROJECT" == "" ]; then
            	echo "Warning: No selected project"
            	echo "You can still proceed to execute anyway or press Ctrl-C to exit"
            else
            	echo "Please confirm your target project is $PROJECT"
            fi
            pause
            task=${START_TASK:-$([ "$(echo $@ | wc -w)" -ge "2" ] && echo $2 || echo "1")}
            echo "Starting from task $task"
            echo ""
    		echo "No argument will be able to passed to any task."
    		echo "Are you sure you wanna do all at once?"
    		pause
    		while [[ $(type -t task$task) == function ]]; do
                splitter
    			task$task
    			task=$(($task + 1))
    		done
    	fi
        ;;
    "help" | "")
        cat << EOF
Usage:
    $0 <task_number> <additional_args_for_task>
        Execute specified task.

    $0 all
        Execute all tasks from task 1.

    START_TASK=<task_number> $0 all
    - or -
    $0 all <task_number>
        Execute tasks start from specified task.

    $0 help
        Display this message
EOF
        ;;
    *)
        if [ "$PROJECT" == "" ]; then
        	echo "Warning: No selected project"
        	echo "You can still proceed to execute anyway or Ctrl-C to exit"
        else
        	echo "Please confirm your target project is $PROJECT"
        fi
        pause
        splitter
	    [[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
        ;;
esac

