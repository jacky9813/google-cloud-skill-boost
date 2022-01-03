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
    if [ -z "$GLOBAL_NON_STOP" ]; then
        read -p "Press Enter to continue"
    fi
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
CLUSTER_NAME=echo-cluster
DEPLOY_NAME=echo-web
IMG_NAME=echo-app
REMOTE_IMG_NAME=gcr.io/$PROJECT/$IMG_NAME
REPLICAS=2

task1(){
cat << EOF
Task 1 - Preparing challenge scenario
$(splitter)
EOF
pause

echo_cmd gsutil ls gs://$PROJECT
echo_cmd gcloud container clusters list --filter=name:$CLUSTER_NAME

echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE
echo_cmd kubectl create deployment $DEPLOY_NAME --image=gcr.io/qwiklabs-resources/echo-app:v1
echo_cmd kubectl expose deployment $DEPLOY_NAME --type=LoadBalancer --port=80 --target-port=8000

splitter
echo "Waiting for load balancer getting ready..."
LB_IP=$(kubectl get service/$DEPLOY_NAME | grep $DEPLOY_NAME | awk '{print $4}')
while [ "$LB_IP" == "<pending>" ]; do
sleep 1
LB_IP=$(kubectl get service/$DEPLOY_NAME | grep $DEPLOY_NAME | awk '{print $4}')
done

} # End of task 1

task2(){
cat << EOF
Task 2 - Build a new version of container image
$(splitter)
EOF
pause

echo_cmd gsutil cp gs://$PROJECT/echo-web-v2.tar.gz ./
echo_cmd mkdir echo-web-v2
echo_cmd tar xvzf echo-web-v2.tar.gz -C ./echo-web-v2
echo_cmd docker build -t $IMG_NAME:v2 ./echo-web-v2
echo_cmd docker tag $IMG_NAME:v2 $REMOTE_IMG_NAME:v2
echo_cmd docker push $REMOTE_IMG_NAME:v2
checkpoint
} # End of task 2

task3(){
cat << EOF
Task 3 - Upgrading and scaling deployment
$(splitter)
EOF

echo_cmd "kubectl patch deployment $DEPLOY_NAME --type=json -p='[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\":\"$REMOTE_IMG_NAME:v2\"}]'"
echo_cmd kubectl scale deployment/$DEPLOY_NAME --replicas=$REPLICAS

checkpoint

echo "Waiting for load balancer getting ready..."
LB_IP=$(kubectl get service/$DEPLOY_NAME | grep $DEPLOY_NAME | awk '{print $4}')
while [ "$LB_IP" == "<pending>" ]; do
sleep 1
LB_IP=$(kubectl get service/$DEPLOY_NAME | grep $DEPLOY_NAME | awk '{print $4}')
done

echo "Waiting the new version getting ready..."
POD_COUNT=$(kubectl get pods -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | grep $DEPLOY_NAME | grep Running | wc -l)
while [ "$POD_COUNT" -lt "$REPLICAS" ] ; do
    sleep 1
    POD_COUNT=$(kubectl get pods -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | grep $DEPLOY_NAME | grep Running | wc -l)
done

echo_cmd curl http://$LB_IP

} # End of task 3

run_all(){
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
}

case "$1" in
    "all")
        run_all $@
        ;;
    "non-stop")
        GLOBAL_NON_STOP=1
        run_all $@
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

    $0 non-stop [task_number]
        Like "all" command but will not pause if executed as expected.

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

