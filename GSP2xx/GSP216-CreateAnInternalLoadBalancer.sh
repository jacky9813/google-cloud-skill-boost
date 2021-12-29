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
VPC=my-internal-app
LB=my-ilb
LB_FW_RULE=$LB-forwarding-rule
LB_IP=$LB-ip
LB_IP_ADDRESS=10.10.30.5

task1(){
    cat << EOF
Task 1 - Preparation
$(splitter)
In this task, we'll create the following resources:
* Firewall rule (app-allow-http) - allow any host ingress via VPC $VPC to access http
* Firewall rule (app-allow-health-check) - allow health checker ingress to access http
* Instance template (instance-template-1) - inside subnet "subnet-a", using startup-script in gs://cloud-training/gcpnet/ilb/startup.sh, tagged with "lb-backend"
* Instance template (instance-template-2) - inside subnet "subnet-b", using startup-script in gs://cloud-training/gcpnet/ilb/startup.sh, tagged with "lb-backend"
* Managed instance group (instance-group-1) - Use the instance-template-1 create 1-5 instances in $REGION-a
* Managed instance group (instance-group-2) - Use the instance-template-2 create 1-5 instances in $REGION-b
* Instance (utility-vm) - f1-micro machine, for testing the connectivity.

After the creation, we'll test the connectivity between utility-vm and 2 instance groups.
EOF
    pause
    # HTTP firewall rule
    echo_cmd gcloud compute firewall-rules create app-allow-http \
        --network=$VPC \
        --target-tags=lb-backend \
        --source-ranges=0.0.0.0/0 \
        --rules=tcp:80 \
        --direction=INGRESS \
        --action=ALLOW
    # health check rule
    echo_cmd gcloud compute firewall-rules create app-allow-health-check \
        --target-tags=lb-backend \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --rules=tcp \
        --direction=INGRESS \
        --action=ALLOW
    
    checkpoint

    # Creating instance templates
    echo_cmd gcloud compute instance-templates create instance-template-1 \
        --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
        --network=$VPC --subnet=subnet-a \
        --tags=lb-backend --region=$REGION
    echo_cmd gcloud compute instance-templates create instance-template-2 \
        --metadata=startup-script-url=gs://cloud-training/gcpnet/ilb/startup.sh \
        --network=$VPC --subnet=subnet-b \
        --tags=lb-backend --region=$REGION

    # Creating managed instance group and auto scaling rules
    echo_cmd gcloud compute instance-groups managed create instance-group-1 \
        --zone=$REGION-a --template=instance-template-1 --size=1
    echo_cmd gcloud compute instance-groups managed set-autoscaling instance-group-1 \
        --zone=$REGION-a \
        --min-num-replicas=1 --max-num-replicas=5 \
        --target-cpu-utilization=0.8 --scale-based-on-cpu \
        --cool-down-period=45s

    echo_cmd gcloud compute instance-groups managed create instance-group-2 \
        --zone=$REGION-b --template=instance-template-2 --size=1
    echo_cmd gcloud compute instance-groups managed set-autoscaling instance-group-2 \
        --zone=$REGION-b \
        --min-num-replicas=1 --max-num-replicas=5 \
        --target-cpu-utilization=0.8 --scale-based-on-cpu \
        --cool-down-period=45s

    # Creating a utility vm
    echo_cmd gcloud compute instances create utility-vm \
        --zone=$REGION-f \
        --network-interface=network=$VPC,subnet=subnet-a,private-network-ip=10.10.20.50 \
        --machine-type=f1-micro

    splitter
    echo "Wait 10 secs for all VMs being ready..."
    sleep 10

    checkpoint

    splitter
    echo "Fetching information about the instances..."
    IG1_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:instance-group-1*" --limit=1 | tail -n +2)
    IG2_IP=$(gcloud compute instances list --format="csv(INTERNAL_IP)" --filter="name:instance-group-2*" --limit=1 | tail -n +2)

    echo_cmd "gcloud compute ssh utility-vm --zone=$REGION-f --command='curl $IG1_IP'"
    echo_cmd "gcloud compute ssh utility-vm --zone=$REGION-f --command='curl $IG2_IP'"
} # End of task 1

task2(){
    cat << EOF
Task 2 - Configure the Internal Load Balancer
$(splitter)
In this task, we'll create an Internal TCP Load Balancer with these settings:
Backend Service:
    Health check:
        Name: $LB-health-check
        Port: 80
        Region: $REGION
    Backends:
        * instance-group-1
        * instance-group-2
    Scheme: Internal
    Protocol: TCP
    Port: 80
Forwarding Rule:
    IP Address:
        Name: $LB_IP
        Subnet: subnet-b
        Address: $LB_IP_ADDRESS

EOF
    pause

    # Create TCP health check
    echo_cmd gcloud compute health-checks create tcp $LB-health-check \
        --port=80 \
        --region=$REGION

    # Create TCP based backend service
    echo_cmd gcloud compute backend-services create $LB \
        --region=$REGION \
        --load-balancing-scheme=INTERNAL \
        --health-checks=$LB-health-check --health-checks-region=$REGION \
        --protocol=TCP
    echo_cmd gcloud compute backend-services add-backend $LB \
        --region=$REGION \
        --instance-group=instance-group-1 --instance-group-zone=$REGION-a
    echo_cmd gcloud compute backend-services add-backend $LB \
        --region=$REGION \
        --instance-group=instance-group-2 --instance-group-zone=$REGION-b

    # Creating frontend
    echo_cmd gcloud compute addresses create $LB_IP \
        --region=$REGION \
        --subnet=subnet-b --addresses=$LB_IP_ADDRESS
    echo_cmd gcloud compute forwarding-rules create $LB_FW_RULE \
        --region=$REGION \
        --network=$VPC --subnet=subnet-b --subnet-region=$REGION \
        --load-balancing-scheme=INTERNAL \
        --backend-service=$LB \
        --address=$LB_IP --address-region=$REGION \
        --ports=80

    checkpoint
} # End of task 2

task3(){
    cat << EOF
Task 3 - Test the Internal Load Balancer
$(splitter)
In this task, we'll test the Internal Load Balancer using utility-vm.
EOF
    pause
    echo_cmd "gcloud compute ssh utility-vm --zone=$REGION-f --command='for i in \$(seq 5);do sleep 1; curl $LB_IP_ADDRESS;done;'"
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

