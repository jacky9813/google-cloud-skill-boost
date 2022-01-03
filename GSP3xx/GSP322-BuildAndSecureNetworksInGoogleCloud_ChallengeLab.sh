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
    echo ""
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
ZONE=us-central1-b
VPC=acme-vpc

task1(){
cat << EOF
Task 1 - Delete overly open firewall rule
$(splitter)
EOF
pause
echo_cmd gcloud compute firewall-rules delete open-access
checkpoint
} # End of task 1

task2(){
cat << EOF
Task 2 - Start "bastion" instance
$(splitter)
EOF
pause
echo_cmd gcloud compute instances start bastion --zone=$ZONE
checkpoint
} # End of task 2

task3(){
echo "Preparing task 3..."
MGMT_NET=$(gcloud compute networks subnets list --filter="name:acme-mgmt-subnet" --format="csv(RANGE)" --limit=1 | tail -n +2)
read -p "Please paste the tag for allowing IAP SSH access: " TAG_IAP_SSH
read -p "Please paste the tag for HTTP access: " TAG_HTTP
read -p "Please paste the tag for allowing internal SSH access: " TAG_INT_SSH
splitter
cat << EOF
Task 3 - Create proper firewall rules
$(splitter)
Here's the firewall rules to be created:
Name                            Rule    Source              Target
=======================================================================
acme-vpc-allow-iap-ssh-ingress  tcp:22  35.235.240.0/20     tag($TAG_IAP_SSH)
acme-vpc-allow-http-ingress     tcp:80  any                 tag($TAG_HTTP)
acme-vpc-allow-internal-ssh     tcp:22  $MGMT_NET     tag($TAG_INT_SSH)
EOF
pause

# SSH IAP rule
echo_cmd gcloud compute firewall-rules create acme-vpc-allow-iap-ssh-ingress \
    --network=$VPC \
    --source-ranges=35.235.240.0/20 \
    --target-tags=$TAG_IAP_SSH \
    --rules=tcp:22 \
    --direction=INGRESS \
    --action=ALLOW
echo_cmd gcloud compute instances add-tags bastion --zone=$ZONE --tags=$TAG_IAP_SSH

# HTTP public access rule
echo_cmd gcloud compute firewall-rules create acme-vpc-allow-http-ingress \
    --network=$VPC \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$TAG_HTTP \
    --rules=tcp:80 \
    --direction=INGRESS \
    --action=ALLOW

# Internal SSH rule
echo_cmd gcloud compute firewall-rules create acme-vpc-allow-internal-ssh \
    --network=$VPC \
    --source-ranges=$MGMT_NET \
    --target-tags=$TAG_INT_SSH \
    --rules=tcp:22 \
    --direction=INGRESS \
    --action=ALLOW
echo_cmd gcloud compute instances add-tags juice-shop --zone=$ZONE --tags=$TAG_INT_SSH,$TAG_HTTP

checkpoint
} # End of task 3

task4(){
TARGET_IP=$(gcloud compute instances list --filter="name:juice-shop" --format="csv(INTERNAL_IP)" --limit=1 | tail -n +2)
cat << EOF
Task 4 - Connect to "juice-shop" via IAP SSH session to bastion
$(splitter)
This task cannot be done here. Go to the "Compute Engine" => "VM Instances" page on Google Cloud Platform console, enter this command:
\`\`\`
ssh $TARGET_IP
\`\`\`

It should be able to establish connection to juice-shop.
EOF
pause
}

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

