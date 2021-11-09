#!/bin/bash

PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
ZONE=us-central1-b
CLUSTER_NAME=io
CONTAINER_NAME=nginx
EXPOSE_PORT=80
TSK4_FWD_PORT=10080
TSK5_FW_RULE=allow-monolith-nodeport

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
# Setting up default zone
echo_cmd gcloud config set compute/zone $ZONE

# Creating a cluster for future tasks
echo_cmd gcloud container clusters create $CLUSTER_NAME

# Retrieve credential data from the cluster
echo_cmd gcloud container clusters get-credentials $CLUSTER_NAME

# Copy sample files for GSP021
echo 'Here I added "-m" flag to the following command as gsutil suggest it will be faster with multi-tasking enabled'
echo_cmd gsutil -m cp -r gs://spls/gsp021/* .

# Copying this script to orchestrate-with-kuvernetes/kubernetes
echo_cmd cp $(realpath $0) orchestrate-with-kubernetes/kubernetes

# Notify
cat << EOF
Change directory to orchestrate-with-kubernetes/kubernetes then continue.
This script has been copied to there.
EOF
}

task2(){
cat << EOF 
Task 2 - Quick Kubernetes Demo
A quick example to deploy container without any yaml file.
EOF

# Creating a pod
echo_cmd kubectl create deployment $CONTAINER_NAME --image=nginx:1.10.0

# Get a pod list
echo_cmd kubectl get pods

# Expose created pod
echo_cmd kubectl expose deployment $CONTAINER_NAME --port=$EXPOSE_PORT --type=LoadBalancer

# Get exposed IP address
IP_ADDRESS=$(kubectl get services | grep $CONTAINER_NAME | awk '{print$4}')
echo "Waiting for load balancer get its IP address"
while [ "$IP_ADDRESS" == "<pending>" ]; do
	sleep 1
	IP_ADDRESS=$(kubectl get services | grep $CONTAINER_NAME | awk '{print$4}')
done
echo_cmd kubectl get services

# Load balancer needs a few second to fully operational
echo "Waiting 10 seconds for letting load balancer fully ready"
sleep 10

# Test
echo "IP address for load balancer is $IP_ADDRESS"
echo_cmd curl http://$IP_ADDRESS:$EXPOSE_PORT

# Quest checkpoint
echo "Checkpoint reached"
pause
}

task3(){
echo "Task 3 - Experiment with Pods (Preparation for task 4)"
POD_YAML=pods/monolith.yaml

# Check file existence
if [ -f "$POD_YAML" ]; then
# Show the content of yaml file
echo_cmd cat $POD_YAML

# Create a pod as the yaml file describes
echo_cmd kubectl create -f $POD_YAML

# Check the pod
echo_cmd kubectl get pods
echo_cmd kubectl describe pods monolith
else
	echo "$POD_YAML not found"
	exit 1
fi
}

task4(){
cat << EOF
Task 4 requires multiple workers.
Use "$0 4-1", "$0 4-2" and "$0 4-3" on different cloud terminal."
EOF
}

task4-1(){
cat <<EOF
Task 4 - Interacting with Pods - First Terminal (Tester)
First Terminal requires second terminal forwarding packet. If you get any error, check it first.
You can run first terminal program as many times you want.
EOF
pause

echo_cmd curl http://localhost:$TSK4_FWD_PORT
pause

echo_cmd curl http://localhost:$TSK4_FWD_PORT/secure
pause

echo ================================================================================
cmd="curl -u user http://127.0.0.1:$TSK4_FWD_PORT/login"
echo $cmd
echo "The password for this example is \"password\""
TOKEN=$($cmd | jq -r '.token')
if [ "$TOKEN" == "" ]; then
echo "Failed to get a token"
exit 1
else
echo "Got token: $TOKEN"
fi
pause

echo ================================================================================
echo "curl -H \"Authorization: Bearer $TOKEN\" http://localhost:$TSK4_FWD_PORT/secure"
curl -H "Authorization: Bearer $TOKEN" http://localhost:$TSK4_FWD_PORT/secure
pause

echo_cmd curl http://localhost:$TSK4_FWD_PORT
pause

# Enters the terminal inside a pod
echo_cmd kubectl exec monolith --stdin --tty -c monolith /bin/sh
}

task4-2(){
cat << EOF
Task 4 - Interacting with Pods - Second Terminal (Port Forwarder)
(Use Ctrl-C to terminate forwarding process)
EOF
echo_cmd kubectl port-forward monolith $TSK4_FWD_PORT:80
}

task4-3(){
cat << EOF
Task 4 - Interacting with Pods - Third Terminal (container log terminal)
(Use Ctrl-C to exit log following)
EOF
echo_cmd kubectl logs -f monolith
}

task5(){
echo "Task 5 - Creating a Service"
POD_YAML=pods/secure-monolith.yaml
SRV_YAML=services/monolith.yaml
if [ -f "$POD_YAML" ] && [ -f "$SRV_YAML" ]; then
    echo_cmd cat $POD_YAML

# Create a secure volume for TLS storage
    echo_cmd kubectl create secret generic tls-certs --from-file tls/

# Create a configuration volume
    echo_cmd kubectl create configmap nginx-proxy-conf --from-file nginx/proxy.conf

# Create pod
    echo_cmd kubectl create -f $POD_YAML

    echo_cmd cat $SRV_YAML

# Create service (expose port)
    echo_cmd kubectl create -f $SRV_YAML
    echo "Checkpoint reached"
    pause

# Create Google Cloud firewall rule
    echo_cmd gcloud compute firewall-rules create $TSK5_FW_RULE --allow=tcp:31000

    echo "Checkpoint reached"
    pause

# Get one of the external IP address from all instances.
    echo_cmd gcloud compute instances list
    IP_ADDRESS=$(gcloud compute instances list | grep EXTERNAL_IP | head -n 1 | sed "s/^[^1-9]*//" )
    if [ "$IP_ADDRESS" == "" ] ; then
        echo "ERROR: Unable to get IP address from any of the instances."
    else
        echo "Using IP address: $IP_ADDRESS"

# Execute the command as instructed.
        echo "The following command is expected to spit out error."
        echo_cmd curl -k https://$IP_ADDRESS:31000
        echo ""
    fi
else
cat << EOF
Either pod descriptor file $POD_YAML or service descriptor $SRC_YAML (or both files) not found
EOF
fi
}

task6(){
cat << EOF
Task 6 - Adding Labels to Pods
The secure-monolith pod is created, but monolith service specified all pods to providing service must have label "secure" with value "enabled".
This task will add the "secure" label on secure-monolith pod.
EOF

# List all pods with label app=monolith
echo_cmd kubectl get pods -l "app=monolith"
pause

# List all pods with label app=monolith and secure=enabled
echo_cmd kubectl get pods -l "app=monolith,secure=enabled"
cat << EOF
================================================================================
This should explain why at the end of task 5, the request has failed.
From now on, the process will add label "secure=enabled" to secure-monolith pod
EOF
pause

# Add label to secure-monolith
echo_cmd kubectl label pods secure-monolith 'secure=enabled'

# Check secure-monolith's label
echo_cmd kubectl get pods secure-monolith --show-labels
cat << EOF
================================================================================
You should have noticed the label "secure=enabled" is now present.
EOF
pause

echo_cmd "kubectl describe services monolith | grep Endpoints"
cat << EOF
================================================================================
And this command should have picked up secure-monolith as one of monolith service's worker.
EOF
pause

echo_cmd gcloud compute instances list
IP_ADDRESS=$(gcloud compute instances list | grep EXTERNAL_IP | head -n 1 | sed "s/^[^1-9]*//" )
if [ "$IP_ADDRESS" == "" ]; then
    echo "ERROR: Unable to get IP address from any of instances."
else
    echo "Using IP address: $IP_ADDRESS"
    echo_cmd curl -k https://$IP_ADDRESS:31000
fi
echo "Checkpoint reached"
pause
}

task7(){
AUTH_POD_YAML=deployments/auth.yaml
AUTH_SRV_YAML=services/auth.yaml
HELLO_POD_YAML=deployments/hello.yaml
HELLO_SRV_YAML=services/hello.yaml
FRONTEND_POD_YAML=deployments/frontend.yaml
FRONTEND_SRV_YAML=services/frontend.yaml
cat << EOF
Task 7 - Creating Deployments
Instead of creating one big pod with all services stuff inside,
you can split services into multiple pods.

Task 7 will be focus on the process of creating all service pods.
Feel free to take a look inside of all files related to this deployment:
$AUTH_POD_YAML
$AUTH_SRV_YAML
$HELLO_POD_YAML
$HELLO_SRV_YAML
$FRONTEND_POD_YAML
$FRONTEND_SRV_YAML
EOF
pause
# As most process has been explained in monolith deployment, the comment in this
# section will be reduced.

# File check
if  [ -f "$AUTH_POD_YAML" ] && \
    [ -f "$AUTH_SRV_YAML" ] && \
    [ -f "$HELLO_POD_YAML" ] && \
    [ -f "$HELLO_SRV_YAML" ] && \
    [ -f "$FRONTEND_POD_YAML" ] && \
    [ -f "$FRONTEND_SRV_YAML" ]; then
echo_cmd kubectl create -f $AUTH_POD_YAML
echo_cmd kubectl create -f $AUTH_SRV_YAML
echo_cmd kubectl create -f $HELLO_POD_YAML
echo_cmd kubectl create -f $HELLO_SRV_YAML
echo_cmd kubectl create configmap nginx-frontend-conf --from-file=nginx/frontend.conf
echo_cmd kubectl create -f $FRONTEND_POD_YAML
echo_cmd kubectl create -f $FRONTEND_SRV_YAML
IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print$4}')
echo "Waiting for load balancer get its IP address"
while [ "$IP_ADDRESS" == "<pending>" ]; do
	sleep 1
	IP_ADDRESS=$(kubectl get services | grep frontend | awk '{print$4}')
done
echo_cmd kubectl get services frontend
echo "Using IP address $IP_ADDRESS"
echo_cmd curl -k https://$IP_ADDRESS
echo "Checkpoint reached"
pause
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
	[[ $(type -t task$1) == function ]] && task$1 $@ && echo "Task $task completed" || echo "No task named task$1"
fi

