#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
CLUSTER_NAME=bootcamp

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
}

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

