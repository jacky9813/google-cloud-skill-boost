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
BUCKET_NAME=$(cat .gsp301-bucket 2>/dev/null)
BUCKET_NAME=${BUCKET_NAME:-qwiklabs-gsp301-$(dd if=/dev/urandom bs=12 count=1 2>/dev/null | base64 | sed -E "s/[+\/]//g" | awk '{print tolower($0)}')}
echo $BUCKET_NAME > .gsp301-bucket
STARTUP_SCRIPT=install-web.sh
INST_NAME=gsp301-instance

task1(){
cat << EOF
Task 1 - Upload startup script to a new storage bucket
$(splitter)
EOF
pause
# After investigating, the sample script simply installs Apache HTTP server on to the new instance.
cat << EOF > $STARTUP_SCRIPT
#!/bin/bash
apt-get update
apt-get install -y apache2
EOF
echo_cmd gsutil mb gs://$BUCKET_NAME
echo_cmd gsutil cp $STARTUP_SCRIPT gs://$BUCKET_NAME/$STARTUP_SCRIPT
} # End of task 1

task2(){
cat << EOF
Task 2 - Create a instance with startup script on GCS bucket
$(splitter)
EOF
pause
echo_cmd gcloud compute firewall-rules create default-allow-http-gsp301 --allow=tcp:80 --direction=INGRESS --source-ranges=0.0.0.0/0 --target-tags=http-server

# Seems like it only recognize instances in zone us-central1-a. Come on you're not AWS.
echo_cmd gcloud compute instances create $INST_NAME --metadata=startup-script-url=gs://$BUCKET_NAME/$STARTUP_SCRIPT --tags=http-server --zone=us-central1-a

splitter
echo "Fetching external address from $INST_NAME..."
INST_EXT_ADDR=$(gcloud compute instances list --filter="name:$INST_NAME" --format="csv(EXTERNAL_IP)" --limit=1 | tail -n +2)
splitter
echo "Waiting 20 seconds for $INST_NAME getting ready..."
sleep 20
echo_cmd curl -L http://$INST_EXT_ADDR
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

