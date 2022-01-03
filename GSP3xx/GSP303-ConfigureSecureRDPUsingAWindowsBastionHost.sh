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
REGION=us-central1
ZONE=$REGION-a
VPC=securenetwork
SUBNET=securenetwork
SUBNET_RANGE=10.0.0.0/24
BAST_INST_NAME=vm-bastionhost
SEC_INST_NAME=vm-securehost
TAG_BASTION=bastion
WAIT_DURATION=60

task1(){
cat << EOF

EOF
pause
# Create a new VPC and subnet
echo_cmd gcloud compute networks create $VPC --subnet-mode=custom
checkpoint

echo_cmd gcloud compute networks subnets create $SUBNET --network=$VPC --range=$SUBNET_RANGE --region=$REGION
checkpoint

# Firewall rules for the new VPC
echo_cmd gcloud compute firewall-rules create $VPC-allow-external-rdp \
    --network=$VPC \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$TAG_BASTION \
    --rules=tcp:3389 \
    --direction=INGRESS \
    --action=ALLOW
checkpoint

# Creating secured instance
echo_cmd gcloud compute instances create $BAST_INST_NAME \
    --image-project=windows-cloud --image-family=windows-2016 \
    --zone=$ZONE \
    --network-interface=network=$VPC,subnet=$SUBNET \
    --network-interface=network=default,subnet=default,no-address \
    --tags=$TAG_BASTION
checkpoint

echo_cmd gcloud compute instances create $SEC_INST_NAME \
    --image-project=windows-cloud --image-family=windows-2016 \
    --zone=$ZONE \
    --network-interface=network=$VPC,subnet=$SUBNET,no-address \
    --network-interface=network=default,subnet=default,no-address
checkpoint

splitter
echo "Waiting $WAIT_DURATION seconds for all Windows instances being ready..."
sleep $WAIT_DURATION

# Configuring Windows user account
echo_cmd gcloud compute reset-windows-password $BAST_INST_NAME \
    --zone=$ZONE \
    --user=app_admin
splitter
cat << EOF
Use the credential generated above to login to bastion machine with RDP tool.
EOF
gcloud compute instances describe $SEC_INST_NAME --zone=$ZONE --format=json > .gsp303-$SEC_INST_NAME
SEC_INST_DEF_ADDR=$(jq -r ".networkInterfaces[] | select(.network == \"https://www.googleapis.com/compute/v1/projects/$PROJECT/global/networks/default\") | .networkIP" .gsp303-$SEC_INST_NAME)
SEC_INST_VPC_ADDR=$(jq -r ".networkInterfaces[] | select(.network == \"https://www.googleapis.com/compute/v1/projects/$PROJECT/global/networks/$VPC\") | .networkIP" .gsp303-$SEC_INST_NAME)
pause
echo_cmd gcloud compute reset-windows-password $SEC_INST_NAME \
    --zone=$ZONE \
    --user=app_admin
splitter
cat << EOF
Inside $BAST_INST_NAME, connect to $SEC_INST_NAME using address $SEC_INST_VPC_ADDR (preferred) or $SEC_INST_DEF_ADDR with RDP tool and the credentials above.
Then install IIS onto $SEC_INST_NAME
EOF
checkpoint
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

