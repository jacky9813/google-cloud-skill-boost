#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")

# Leave this variable blank if you want to enable doing all tasks at once
DISABLE_ALL_TASK=1

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
task1(){
# TODO: Figure out the path to the repo
REPO_PATH=
cat << EOF
Task 1 - Create a Docker image and store the Dockerfile
EOF
pause

echo_cmd 'gsutil cat gs://cloud-training/gsp318/marking/setup_marking.sh | bash'
echo_cmd gcloud source repos list
pause
echo_cmd git clone $REPO_PATH
cat << EOF > valkyrie-app/Dockerfile
FROM golang:1.10
WORKDIR /go/src/app
COPY source .
RUN go install -v
ENTRYPOINT ["app", "-single=true", "-port=8080"]
EOF

echo_cmd docker build --tag "valkyrie-app:v0.0.1" valkyrie-app/

echo_cmd step1.sh
checkpoint
} # End of task 1

task2(){
cat << EOF
Task 2 - Test the created Docker image
EOF
pause

echo_cmd docker run -d -p 8080:8080 valkyrie-app:v0.0.1
echo_cmd step2.sh
checkpoint
}

task3(){
cat << EOF
Task 3 - Push the Docker image in the Container Repository
EOF
pause
echo_cmd docker tag valkyrie-app:v0.0.1 gcr.io/$PROJECT/valkyrie-app:v0.0.1
echo_cmd docker push gcr.io/$PROJECT/valkyrie-app:v0.0.1
checkpoint
}

task4(){
EDITOR=${EDITOR:-vim}
cat << EOF
Task 4 - Create and expose a deployment in Kubernetes
EOF
pause
echo_cmd gcloud container clusters get-credentials valkyrie-dev
echo_cmd kubectl cluster-info

echo_cmd $EDITOR valkyrie-app/k8s/deployment.yaml
echo_cmd kubectl create -f valkyrie-app/k8s/deployment.yaml
echo_cmd $EDITOR valkyrie-app/k8s/service.yaml
echo_cmd kubectl create -f valkyrie-app/k8s/service.yaml

checkpoint
}

task5(){
cat << EOF
Task 5 - Update the deployment with a new version of valkyrie-app
EOF
pause

echo_cmd kubectl scale --replicas=3 -f valkyrie-app/k8s/deployment.yaml

# Merging the code
splitter
echo "Changing directory into valkyrie-app"
cd valkyrie-app
echo_cmd git merge origin/kurt-dev

# Building the container image and push to the image repository
echo_cmd docker build -t gcr.io/$PROJECT/valkyrie-app:v0.0.2
echo_cmd docker push gcr.io/$PROJECT/valkyrie-app:v0.0.2

checkpoint
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
    		echo "No argument will be able to passed to any task."
    		echo "Are you sure you wanna do all at once?"
    		pause
    		task=${START_TASK:-1}
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
    $0 <task_number>
        Execute specified task.

    $0 all
        Execute all tasks from task 1.

    START_TASK=<task_number> $0 all
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

