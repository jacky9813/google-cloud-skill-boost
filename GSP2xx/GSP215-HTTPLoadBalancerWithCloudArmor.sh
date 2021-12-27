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

REGION_US=us-east1
REGION_EU=europe-west1
ZONE_US=$REGION_US-a
ZONE_EU=$REGION_EU-a

# TODO: PUT THE TASKS HERE
task1(){
cat << EOF
Task 1 - Setup HTTP servers and health checks
$(splitter)

EOF
pause
echo_cmd gcloud compute firewall-rules create default-allow-http --target-tags=http-server --source-ranges=0.0.0.0/0 --rules=tcp:80 --action=ALLOW --direction=INGRESS
echo_cmd gcloud compute firewall-rules create defult-allow-health-check --target-tags=http-server --source-ranges=130.211.0.0/22,35.191.0.0/16 --rules=tcp --action=ALLOW --direction=INGRESS
checkpoint

# Creating same template on 2 different regions
echo_cmd gcloud compute instance-templates create $REGION_US-template --tags=http-server --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh --network=default --subnet=default --region=$REGION_US
echo_cmd gcloud compute instance-templates create $REGION_EU-template --tags=http-server --metadata=startup-script-url=gs://cloud-training/gcpnet/httplb/startup.sh --network=default --subnet=default --region=$REGION_EU

# Create instance group based on the template
echo_cmd gcloud compute instance-groups managed create $REGION_US-mig --region=$REGION_US --template=$REGION_US-template --size=1
echo_cmd gcloud compute instance-groups set-named-ports $REGION_US-mig --named-ports=http:80 --region=$REGION_US
# I'm not sure if this command achieves creating instances on multiple zones or not.
echo_cmd gcloud compute instance-groups managed set-autoscaling $REGION_US-mig --region=$REGION_US --min-num-replicas=1 --max-num-replicas=5 --cool-down-period=45s --scale-based-on-cpu --target-cpu-utilization=0.8
# And the EU one
echo_cmd gcloud compute instance-groups managed create $REGION_EU-mig --region=$REGION_EU --template=$REGION_EU-template --size=1
echo_cmd gcloud compute instance-groups set-named-ports $REGION_EU-mig --named-ports=http:80 --region=$REGION_EU
echo_cmd gcloud compute instance-groups managed set-autoscaling $REGION_EU-mig --region=$REGION_EU --min-num-replicas=1 --max-num-replicas=5 --cool-down-period=45s --scale-based-on-cpu --target-cpu-utilization=0.8
checkpoint

# Verify the instances
splitter
echo "Fetching IP..."
INST_US_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --limit=1 --filter="name:$REGION_US-mig*" | tail -n +2)
INST_EU_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --limit=1 --filter="name:$REGION_EU-mig*" | tail -n +2)

echo_cmd curl $INST_US_EXT_IP
echo_cmd curl $INST_EU_EXT_IP
} # End of task 1

task2(){
cat << EOF
Task 2 - Configure HTTP load balancers
$(splitter)
EOF
pause

# Create health check using default values
echo_cmd gcloud compute health-checks create tcp http-health-check --global --port=80
# Create backend service
echo_cmd gcloud compute backend-services create http-backend --health-checks=http-health-check --port-name=http --protocol=HTTP --global
echo_cmd gcloud compute backend-services add-backend http-backend --instance-group=$REGION_US-mig --instance-group-region=$REGION_US --balancing-mode=RATE --max-rate-per-instance=50 --global
echo_cmd gcloud compute backend-services add-backend http-backend --instance-group=$REGION_EU-mig --instance-group-region=$REGION_EU --balancing-mode=UTILIZATION --max-utilization=0.8 --capacity-scaler=1.0 --global

# Create url map and proxy
PROXY=http-lb-forwarding-rule-target-proxy
echo_cmd gcloud compute url-maps create http-lb --default-service=http-backend --global
echo_cmd gcloud compute target-http-proxies create $PROXY --url-map=http-lb --global --global-url-map

# Create frontend
echo_cmd gcloud compute forwarding-rules create http-lb-forwarding-rule --target-http-proxy=$PROXY --ports=80 --load-balancing-scheme=EXTERNAL --global --network-tier=PREMIUM
echo_cmd gcloud compute forwarding-rules create http-lb-forwarding-rule-2 --target-http-proxy=$PROXY --ports=80 --ip-version=IPV6 --load-balancing-scheme=EXTERNAL --global --network-tier=PREMIUM
checkpoint

} # End of task 2

task3(){
echo -ne "Preparing task 3...\r"
LB_IPV4=$(gcloud compute forwarding-rules list --format="csv(IP_ADDRESS)" --filter="name:http-lb-forwarding-rule" --limit=1 | tail -n +2)
LB_IPV6="[$(gcloud compute forwarding-rules list --format='csv(IP_ADDRESS)' --filter='name:http-lb-forwarding-rule-2' --limit=1 | tail -n +2)]"
cat << EOF
Task 3 - Test load balancer
$(splitter)
EOF
pause

# Creating testing instance(s)
echo_cmd gcloud compute instances create siege-vm --zone=$REGION_US-c
splitter
echo "Wait 10 secs for siege-vm starting up"
sleep 10
echo_cmd "gcloud compute ssh siege-vm --zone=$REGION_US-c --command='sudo apt update;sudo apt install -y siege'"
echo_cmd "gcloud compute ssh siege-vm --zone=$REGION_US-c --command='siege -c 250 http://$LB_IPV4'"
} # End of task 3

task4(){
SIEGE_VM_EXT_IP=$(gcloud compute instances list --format="csv(EXTERNAL_IP)" --filter="name:siege-vm" --limit=1 | tail -n +2)
LB_IPV4=$(gcloud compute forwarding-rules list --format="csv(IP_ADDRESS)" --filter="name:http-lb-forwarding-rule" --limit=1 | tail -n +2)
echo -ne "Preparing task 4...\r"
cat << EOF
Task 4 - Blacklist siege-vm
$(splitter)
EOF
pause

# Create Cloud Armor policy
echo_cmd gcloud compute security-policies create denylist-siege
echo_cmd gcloud compute security-policies rules create 1000 --action=deny-403 --security-policy=denylist-siege --src-ip-ranges=$SIEGE_VM_EXT_IP
echo_cmd gcloud compute security-policies rules update 2147483647 --action=allow --security-policy=denylist-siege --src-ip-ranges=\*

# Apply Policy to backend service
echo_cmd gcloud compute backend-services update http-backend --security-policy=denylist-siege --global

checkpoint

# Verify new policy
echo_cmd "gcloud compute ssh siege-vm --zone=$REGION_US-c --command='curl http://$LB_IPV4'"
echo_cmd "gcloud compute ssh siege-vm --zone=$REGION_US-c --command='siege -c 250 http://$LB_IPV4'"
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

