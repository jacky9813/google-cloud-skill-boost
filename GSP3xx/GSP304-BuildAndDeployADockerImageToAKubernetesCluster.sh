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

CLUSTER_NAME=echo-cluster
CLUSTER_MACHINE_TYPE=n1-standard-2

IMG_NAME=echo-app
REMOTE_IMG_NAME=gcr.io/$PROJECT/$IMG_NAME

DEPLOY_NAME=echo-web
DEPLOY_YAML=deployment-$DEPLOY_NAME.yaml
SVC_NAME=echo-app
SVC_YAML=service-$SVC_NAME.yaml
LABEL_APP=$DEPLOY_NAME


task1(){
cat << EOF
Task 1 - Creating a Kubernetes cluster
$(splitter)
In this task, we'll create a Kubernetes cluster inside $ZONE called $CLUSTER_NAME
EOF
pause
echo_cmd gcloud container clusters create $CLUSTER_NAME \
    --machine-type=$CLUSTER_MACHINE_TYPE \
    --zone=$ZONE
checkpoint
} # End of task 1

task2(){
cat << EOF
Task 2 - Building a Docker image
$(splitter)
Using the pre-existing file in gs://$PROJECT/echo-web.tar.gz, we'll build and upload a docker image to project's image registry.
EOF
pause

# Download code
echo_cmd gsutil cp gs://$PROJECT/echo-web.tar.gz ./
echo_cmd tar xzvf echo-web.tar.gz

# Build container
echo_cmd docker build -t $IMG_NAME:v1 ./echo-web

# Upload container
echo_cmd docker tag $IMG_NAME:v1 $REMOTE_IMG_NAME:v1
echo_cmd docker push $REMOTE_IMG_NAME:v1
checkpoint
} # End of task 2

task3(){
cat << EOF
Task 3 - Deploy the image
$(splitter)
In this task, we'll deploy the image we've created in the last task to the cluster.
EOF
pause

# Preparing kubectl
echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME --zone=$ZONE
cat << EOF > $DEPLOY_YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOY_NAME
  labels:
    app: $LABEL_APP
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $LABEL_APP
  template:
    metadata:
      labels:
        app: $LABEL_APP
    spec:
      containers:
      - name: $LABEL_APP
        image: $REMOTE_IMG_NAME:v1
        ports:
        - containerPort: 8000
EOF
cat << EOF > $SVC_YAML
apiVersion: v1
kind: Service
metadata:
  name: $SVC_NAME
spec:
  selector:
    app: $LABEL_APP
  ports:
  - port: 80
    targetPort: 8000
  type: LoadBalancer
EOF
splitter
cat $DEPLOY_YAML
splitter
cat $SVC_YAML
echo_cmd kubectl apply -f $DEPLOY_YAML
echo_cmd kubectl apply -f $SVC_YAML
splitter
echo "Checking IP address..."
LB_ADDR=$(kubectl get service | grep $SVC_NAME | awk '{print $4}')
while [ "$LB_ADDR" == "<pending>" ]; do
    sleep 1
    LB_ADDR=$(kubectl get service | grep $SVC_NAME | awk '{print $4}')
done
cat << EOF
Test the connection by opening a browser tab with URL: "http://$LB_ADDR"
EOF
checkpoint
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

