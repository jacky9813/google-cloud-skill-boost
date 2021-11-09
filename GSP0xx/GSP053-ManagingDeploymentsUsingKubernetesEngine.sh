#!/bin/bash
# GSP053 - Managing Deployments Using Kubernetes Engine
#
# This course should be taken after GSP021 or other basic kubernetes deployment courses.
#

PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
CLUSTER_NAME=bootcamp

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=

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
cat << EOF
Task 1 - Preparation
EOF
# Setting up default zone
echo_cmd gcloud config set compute/zone us-central1-a

# Retrieving sample code
echo_cmd gsutil -m cp -r gs://spls/gsp053/orchestrate-with-kubernetes .

# Create 5 node cluster
echo_cmd gcloud container clusters create $CLUSTER_NAME \
    --num-nodes=5 \
    --scopes="https://www.googleapis.com/auth/projecthosting,storage-rw"

# Setup kubernetes credentials
echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME

# Copy this script
echo_cmd cp $(realpath $0) orchestrate-with-kubernetes/kubernetes/

cat << EOF
================================================================================
  Please switch to orchestrate-with-kubernetes/kubernetes to continue.
  This script file has been copied to there.
================================================================================
EOF
} # End of task 1

task2(){
AUTH_DEPLOY_YAML=deployments/auth.yaml
cat << EOF
Task 2 - Create a deployment

Change the auth container's image to "kelseyhightower/auth:1.0.0"
EOF
pause
if [ "$EDITOR" == "" ]; then
# Defaults to VIM
vim $AUTH_DEPLOY_YAML
else
# Use user preferred editor
$EDITOR $AUTH_DEPLOY_YAML
fi
cat $AUTH_DEPLOY_YAML | grep "kelseyhightower/auth:1.0.0" > /dev/null
echo_cmd cat $AUTH_DEPLOY_YAML
if ! [ -z "$?" ]; then
    echo "Check the configuration file $AUTH_DEPLOY_YAML again."
    exit 1
fi

# Creating pod(s)
echo_cmd kubectl create -f $AUTH_DEPLOY_YAML

# Series of deployment status checks.
echo_cmd kubectl get deployments
echo "Verify if the deployment has successed."
pause

echo_cmd kubectl get replicasets
echo "Verify the Replica Sets has been created."
pause

echo_cmd kubectl get pods
echo "Verify the pods has been created."
pause

# Create remaining deployments
echo_cmd kubectl create -f services/auth.yaml
echo_cmd kubectl create -f deployments/hello.yaml
echo_cmd kubectl create -f services/hello.yaml
echo_cmd kubectl create secret generic tls-certs --from-file tls/
echo_cmd kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf
echo_cmd kubectl create -f deployments/frontend.yaml
echo_cmd kubectl create -f services/frontend.yaml

cat << EOF
================================================================================
Load balancer is getting ready...
EOF
IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
while [ $IP_ADDRESS == "<pending>" ]; do
    sleep 1
    IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print $4}')
done
sleep 10

echo "Using IP address $IP_ADDRESS"
echo_cmd curl -ks https://$IP_ADDRESS

echo "Checkpoint reached"
pause
} # End of task 2

if [ "$PROJECT" == "" ]; then
	echo "Warning: No selected project"
	echo "You can still proceed to execute anyway or Ctrl-C to exit"
else
	echo "Please confirm your target project is $PROJECT"
fi
pause
if [ "$1" == "all" ]; then
	if [ $DISABLE_ALL_TASK ] ; then
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

