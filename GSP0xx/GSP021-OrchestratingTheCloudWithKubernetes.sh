#!/bin/bash

PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
ZONE=us-central1-b
CLUSTER_NAME=io
CONTAINER_NAME=nginx
EXPOSE_PORT=80

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=1

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
	echo ================================================================================
	echo $@
	$@
}

task1(){
echo "Task 1 - Preparation"
echo_cmd gcloud config set compute/zone $ZONE
echo_cmd gcloud container clusters create $CLUSTER_NAME
echo_cmd gcloud container clusters get_credentials $CLUSTER_NAME
echo_cmd gsutil cp -r gs://spls/gsp021/* .
cat << EOF
change directory to orchestrate-with-kubernetes/kubernetes then continue
EOF
}

task2(){
echo "Task 2 - Quick Kubernetes Demo"
echo_cmd kubectl create deployment $CONTAINER_NAME --image=nginx:1.10.0
echo_cmd kubectl get pods
echo_cmd kubectl expose deployment $CONTAINER_NAME --port=$EXPOSE_PORT --type=LoadBalancer
IP_ADDRESS=$(kubectl get services | grep $CONTAINER_NAME | awk '{print$4}')
echo "Waiting for load balancer get its IP address"
while [ "$IP_ADDRESS" == "" ]; do
	sleep 1
	IP_ADDRESS=$(kubectl get services | grep $CONTAINER_NAME | awk '{print$4}')
done
echo_cmd kubectl get services
echo "IP address for load balancer is $IP_ADDRESS"
echo_cmd curl http://$IP_ADDRESS:$EXPOSE_PORT
echo "Checkpoint reached"
}

task3(){
echo "Task 3 - Experiment with Pods"
POD_YAML=pods/monolith.yaml
if [ -f "$POD_YAML" ]; then
	echo_cmd cat $POD_YAML
	echo_cmd kubectl create -f $POD_YAML
	echo_cmd kubectl get pods
	echo_cmd kubectl describe pods monolith
else
	echo "$POD_YAML not found"
	echo "You may need to change working directory to orchestrate-with-kubernetes/kubernetes to continue"
	exit 1
fi
}


if [ "$PROJECT" == "" ]; then
	echo "Warning: No selected project"
	echo "You can still proceed to execute anyway or Ctrl-C to exit"
else
	echo "Please confirm your target project is $PROJECT"
fi
pause
if [ "$1" == "all" ]; then
	if $DISABLE_ALL_TASK ; then
		echo "Doing all tasks at once has been disabled"
		exit 1
	else
		echo "No argument will be able to passed to any task."
		echo "Are you sure you wanna do all at once?"
		pause
		task=1
		while [[ $(type -t task$task) == function ]]; do
			task$task
			task=$(($task + 1))
		done
	fi
else
	[[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
fi
