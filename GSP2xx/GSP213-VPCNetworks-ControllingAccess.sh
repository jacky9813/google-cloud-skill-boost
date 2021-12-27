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
REGION=us-central1
ZONE=$REGION-a

task1(){
cat << EOF
Task 1 - Prepare blue and green servers
$(splitter)
This task will create two servers as follow:
Property        Blue        Green       TestVM
==============================================
Name            blue        green       test-vm
Zone            $ZONE       $ZONE       $ZONE
Tags            web-server  (None)      (None)
Machine Type    (default)   (default)   f1-micro
EOF
pause
echo_cmd gcloud compute instances create blue --zone=$ZONE --tags=web-server,http-server
checkpoint
echo_cmd gcloud compute instances create green --zone=$ZONE
checkpoint
echo_cmd gcloud compute instances create test-vm --zone=$ZONE --machine-type=f1-micro --subnet=default

echo_cmd "gcloud compute ssh blue --zone=$ZONE --command='sudo apt update ; sudo apt install -y nginx-light'"
echo_cmd "gcloud compute ssh blue --zone=$ZONE --command='cat /var/www/html/index.nginx-debian.html | sed \"s/Welcome to nginx/Welcome to the blue server/g\" | sudo tee /var/www/html/index.nginx-debian.html'"

echo_cmd "gcloud compute ssh green --zone=$ZONE --command='sudo apt update ; sudo apt install -y nginx-light'"
echo_cmd "gcloud compute ssh green --zone=$ZONE --command='cat /var/www/html/index.nginx-debian.html | sed \"s/Welcome to nginx/Welcome to the green server/g\" | sudo tee /var/www/html/index.nginx-debian.html'"

checkpoint
} # End of task 1

task2(){
echo -ne "Preparing task 2...\r"
BLUE_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:blue" | tail -n +2)
BLUE_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:blue" | tail -n +2)
GREEN_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:green" | tail -n +2)
GREEN_INT_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:green" | tail -n +2)
cat << EOF
Task 2 - Create firewall rules and test HTTP connectivity
$(splitter)
Property    Value
====================================
Name        allow-http-web-server
Network     default
Protocols   tcp:80
Direction   INGERSS
Action      ALLOW
Source Net  0.0.0.0/0
Target Tags web-server

EOF
pause
# Allow ingress traffic from anywhere access servers with tag "web-server" via tcp:80
echo_cmd gcloud compute firewall-rules create allow-http-web-server --network=default --target-tags=web-server --rules=tcp:80,icmp --direction=INGRESS --action=ALLOW --source-ranges=0.0.0.0/0
checkpoint

# Test HTTP connectivity
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl $BLUE_INT_IP'"
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl $GREEN_INT_IP'"

echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl $BLUE_EXT_IP'"
# Access green using external IP is expected to be failed.
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl -c 3 $GREEN_EXT_IP ; exit 0'"
} # End of task 2

task3(){
echo -ne "Preparing task 3...\r"
BLUE_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:blue" | tail -n +2)
GREEN_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:green" | tail -n +2)
SA=network-admin
SA_DN=Network-admin
SA_FULL=$SA@$PROJECT.iam.gserviceaccount.com
SA_KEY=credentials.json
cat << EOF
Task 3 - Exploring Network Admin and Security Admin roles
$(splitter)
In this task, we'll create a new service account ($SA) and use its credential inside test-vm.
EOF
pause

# Creating a new service account
echo_cmd gcloud iam service-accounts create $SA --display-name=$SA_DN
# Granting Compute Network Admin role to new service account
echo_cmd gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA_FULL --role=roles/compute.networkAdmin
# Generating JSON credentials
echo_cmd gcloud iam service-accounts keys create $SA_KEY --iam-account=$SA_FULL
checkpoint
# Upload credential to test-vm
echo_cmd gcloud compute scp $SA_KEY test-vm:~ --zone=$ZONE
# Apply new service account credential to gcloud utility
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='gcloud auth activate-service-account --key-file=$SA_KEY'"
# Test newly applied credentials
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='gcloud compute firewall-rules list'"
# How ever, Compute Network Admin does not have firewall modification permission.
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='gcloud compute firewall-rules delete allow-http-web-server; exit 0'"

# Add another role (Compute Security Admin) to Network-admin
echo_cmd gcloud projects add-iam-policy-binding $PROJECT --member=serviceAccount:$SA_FULL --role=roles/compute.securityAdmin
# The listing of firewall rules should work.
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='gcloud compute firewall-rules list'"
# And modifying firewall rules should work as well
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='gcloud compute firewall-rules delete allow-http-web-server'"

# Verify the HTTP connectivity from external IP
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl $BLUE_EXT_IP; exit 0'"
echo_cmd "gcloud compute ssh test-vm --zone=$ZONE --command='curl $GREEN_EXT_IP; exit 0'"

} # End of task 3

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

