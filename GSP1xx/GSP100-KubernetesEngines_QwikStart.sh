#!/bin/bash

PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
CLUSTER_NAME=my-cluster
CONTAINER_NAME=hello-server
EXPOSE_PORT=8080
ZONE=us-central1-a


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
	echo $@
	$@
}

task1(){
echo "Task 1 - Set a default compute zone"
echo_cmd gcloud config set compute/zone $ZONE
}

task2(){
echo "Task 2 - Create a Google Kubernetes Engine (GKE) cluster"
echo_cmd gcloud container clusters create $CLUSTER_NAME
}

task3(){
echo "Task 3 - Get authentication credentials for the cluster"
echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME
}

task4(){
echo "Task 4 - Deploy an application to the cluster"
echo_cmd kubectl create deployment $CONTAINER_NAME --image=gcr.io/google-samples/hello-app:1.0
echo "Reached checkpoint"
pause
echo_cmd kubectl expose deployment $CONTAINER_NAME --type=LoadBalancer --port $EXPOSE_PORT
echo_cmd kubectl get service
IP_ADDRESS=$(kubectl get service | grep $CONTAINER_NAME | awk '{print $4}')
cat << EOF
=========================================================

Goto http://$IP_ADDRESS:$EXPOSE_PORT to view the result
Use "kubectl get service" to check IP again if the IP has not been confirmed.

=========================================================
EOF
}

task5(){
echo "Task 5 - Deleting the cluster"
echo_cmd gcloud container clusters delete $CLUSTER_NAME
}

[[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
