#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=1

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
task1(){
cat << EOF
Task 1 - VPC Network Peering Setup
$(splitter)
In this task, we'll create a subnet and an instance for project A and B.
EOF
pause

splitter
echo "Switching to Project A ($PROJECT_A)"
echo_cmd gcloud config set project $PROJECT_A
echo_cmd gcloud compute networks create network-a --subnet-mode custom
echo_cmd gcloud compute networks subnets create network-a-central --network network-a --range 10.0.0.0/16 --region us-central1
echo_cmd gcloud compute instances create vm-a --zone us-central1-a --network network-a --subnet network-a-central
echo_cmd gcloud compute firewall-rules create network-a-fw --network network-a --allow tcp:22,icmp
checkpoint

splitter
echo "Switching to Project B ($PROJECT_B)"
echo_cmd gcloud config set project $PROJECT_B
echo_cmd gcloud compute networks create network-b --subnet-mode custom
echo_cmd gcloud compute networks subnets create network-b-central --network network-b --range 10.8.0.0/16 --region us-central1
echo_cmd gcloud compute instances create vm-b --zone us-central1-a --network network-b --subnet network-b-central
echo_cmd gcloud compute firewall-rules create network-b-fw --network network-b --allow tcp:22,icmp
checkpoint
}

task2(){
cat << EOF
Task 2 - Setting up a VPC Network Peering session
$(splitter)
In this task, we'll link network-a from project A and network-b from project B.
EOF
pause
echo "Switching to project A ($PROJECT_A)"
echo_cmd gcloud config set project $PROJECT_A
echo_cmd gcloud compute networks peerings create peer-ab --network=network-a --peer-project=$PROJECT_B --peer-network=network-b
checkpoint

echo "Switching to project B ($PROJECT_B)"
echo_cmd gcloud config set project $PROJECT_B
echo_cmd gcloud compute networks peerings create peer-ba --network=network-b --peer-project=$PROJECT_A --peer-network=network-a
checkpoint
}

task3(){
cat << EOF
Task 3 - Test connection
$(splitter)
We've created VPC peering between network-a and network-b.
We can test if the connection between the two.

Since we have opened ICMP on firewall, using ping should work.

We'll ping vm-a from vm-b in this task.
The vm-a's IP address is:
EOF
gcloud compute instances list --zones=us-central1-a --filter="name:vm-a" --format="csv(INTERNAL_IP)" --project=$PROJECT_A
pause

gcloud compute ssh vm-b --zone=us-central1-a --project=$PROJECT_B
}

# Determine Project A and Project B
echo "Projects available:"
gcloud projects list --format="csv(projectId)" 2>/dev/null | tail -n +2
read -p "Which is project A (Enter full project ID): " PROJECT_A
read -p "Which is project B (Enter full project ID): " PROJECT_B
PROJECT_A=$(echo "$PROJECT_A" | xargs)
PROJECT_B=$(echo "$PROJECT_B" | xargs)

case "$1" in
    "all")
    	if [ $DISABLE_ALL_TASK ] ; then
    		echo "Doing all tasks at once has been disabled"
    		exit 1
    	else
    		echo "No argument will be able to passed to any task."
    		echo "Are you sure you wanna do all at once?"
    		pause
    		task=${START_TASK:-1}
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
    $0 <task_number>
        Execute specified task.

    $0 all
        Execute all tasks from task 1.

    START_TASK=<task_number> $0 all
        Execute tasks start from specified task.

    $0 help
        Display this message
EOF
        ;;
    *)
        splitter
	    [[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
        ;;
esac

