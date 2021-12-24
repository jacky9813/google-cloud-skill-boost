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
instance_nat_ip(){
    gcloud compute instances describe $1 --zone=${2:-$ZONE} --format="csv(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | tail -n +2
}

REGION=us-central1
ZONE=$REGION-a
K8S_NAME=private-cluster
MASTER_INST_NAME=source-instance
MASTER_NAT_IP=$(instance_nat_ip $MASTER_INST_NAME)
EXTERNAL_IP_RANGE="$MASTER_NAT_IP/32"
K8S_SUBNET_NAME=my-subnet

task1(){
cat << EOF
Task 1 - Creating a private cluster
$(splitter)
EOF
pause
echo_cmd gcloud config set compute/zone $ZONE
echo_cmd gcloud container clusters create $K8S_NAME --enable-private-nodes --master-ipv4-cidr=172.16.0.16/28 --enable-ip-alias --create-subnetwork=""
checkpoint
} # End of task 1

task2(){
K8S_SUBNET_NAME=$(gcloud compute networks subnets list --network default --filter="name:gke-$K8S_NAME-subnet-*" --format="csv(NAME)" | tail -n +2)
cat << EOF
Task 2 - Viewing subnet and secondary address ranges
$(splitter)
When we creating kubernetes cluster in task 1, we've also created a subnet (using --create-subnetwork flag) without any configuration.
This task solely focuses on examining the subnet created in task 1.

This task will not write anything.
EOF
pause
echo_cmd gcloud compute networks subnets list --network default --filter="name:gke-$K8S_NAME-subnet-*"
echo_cmd gcloud compute networks subnets describe $K8S_SUBNET_NAME --region $REGION
} # End of task 2

task3(){
cat << EOF
Task 3 - Enabling master authorized networks
$(splitter)

EOF
pause
echo_cmd "gcloud compute instances create $MASTER_INST_NAME --zone=$ZONE --scopes='https://www.googleapis.com/auth/cloud-platform'"
checkpoint
echo_cmd "gcloud compute instances describe $MASTER_INST_NAME --zone=$ZONE | grep natIP"
MASTER_NAT_IP=$(instance_nat_ip $MASTER_INST_NAME)
EXTERNAL_IP_RANGE="$MASTER_NAT_IP/32"
echo_cmd gcloud container clusters update $K8S_NAME --enable-master-authorized-networks --master-authorized-networks=$EXTERNAL_IP_RANGE
checkpoint
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='sudo apt install -y kubectl'"
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='gcloud container clusters get-credentials $K8S_NAME --zone=$ZONE'"
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='kubectl get nodes --output yaml | grep -A4 addresses'"
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='kubectl get nodes --output wide'"
} # End of task 3

task4(){
cat << EOF
Task 4 - Clean Up
$(splitter)
EOF
pause
echo_cmd gcloud container clusters delete $K8S_NAME --zone=$ZONE
checkpoint
} # End of task 4

task5(){
K8S_NAME=private-cluster2
K8S_SUBNET_NAME=my-subnet
K8S_SUBNET_SVC_NAME=my-svc-range
K8S_SUBNET_POD_NAME=my-pod-range
cat << EOF
Task 5 - Creating a private cluster that uses a custom subnetwork
$(splitter)
EOF
pause
echo_cmd gcloud compute networks subnets create $K8S_SUBNET_NAME --network=default --range=10.0.4.0/22 --enable-private-ip-google-access --region=$REGION --secondary-range $K8S_SUBNET_SVC_NAME=10.0.32.0/20,$K8S_SUBNET_POD_NAME=10.4.0.0/14
checkpoint
echo_cmd gcloud container clusters create $K8S_NAME --enable-private-nodes --enable-ip-alias --master-ipv4-cidr=172.16.0.32/28 --subnetwork=$K8S_SUBNET_NAME --services-secondary-range-name=$K8S_SUBNET_SVC_NAME --cluster-secondary-range-name=$K8S_SUBNET_POD_NAME
checkpoint
echo_cmd gcloud container clusters update $K8S_NAME --enable-master-authorized-networks --master-authorized-networks=$EXTERNAL_IP_RANGE
checkpoint
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='gcloud container clusters get-credentials $K8S_NAME --zone=$ZONE'"
echo_cmd "gcloud compute ssh $MASTER_INST_NAME --zone=$ZONE --command='kubectl get nodes --output yaml | grep -A4 addresses'"
} # End of task 5

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

