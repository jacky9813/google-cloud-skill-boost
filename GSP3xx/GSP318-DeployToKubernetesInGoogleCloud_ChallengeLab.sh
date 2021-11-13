#!/bin/bash
PROJECT=$(gcloud config list project 2>/dev/null | grep = | sed "s/^[^=]*= //")
EDITOR=${EDITOR:-vim}
ACCOUNT=$(gcloud config list account 2>/dev/null | grep = | sed "s/^[^=]*= //")

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
REPO_PATH=https://source.developers.google.com/p/$PROJECT/r/valkyrie-app
cat << EOF
Task 1 - Create a Docker image and store the Dockerfile
EOF
pause

echo_cmd 'gsutil cat gs://cloud-training/gsp318/marking/setup_marking.sh | bash'
echo_cmd gcloud source repos describe valkyrie-app
pause
echo_cmd git clone $REPO_PATH
# or
# echo_cmd gcloud source reois clone valkyrie-app
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
CONTAINER_NAME=gsp318-valkyrie-app
cat << EOF
Task 2 - Test the created Docker image
EOF
pause

echo_cmd docker run -d -p 8080:8080 --name "$CONTAINER_NAME" valkyrie-app:v0.0.1
echo_cmd step2.sh
checkpoint
echo_cmd docker stop "$CONTAINER_NAME"
echo_cmd docker rm "$CONTAINER_NAME"
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
cat << EOF
Task 4 - Create and expose a deployment in Kubernetes
EOF
pause
echo_cmd gcloud container clusters get-credentials valkyrie-dev
echo_cmd kubectl cluster-info


splitter
cat << EOF
All container (frontend and backend) should use the image gcr.io/$PROJECT/valkyrie-app
Change the deployment.yaml to make that happen.
EOF
pause
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

checkpoint

# Merging the code
splitter
ORIG_WD=$(pwd)
echo "Changing directory into valkyrie-app"
cd valkyrie-app
pwd
echo_cmd git merge origin/kurt-dev

# Building the container image and push to the image repository
echo_cmd docker build -t gcr.io/$PROJECT/valkyrie-app:v0.0.2 .
echo_cmd docker push gcr.io/$PROJECT/valkyrie-app:v0.0.2

echo_cmd kubectl edit deployment/valkyrie-dev

checkpoint

splitter
echo "Changing directory back to $ORIG_WD"
cd $ORIG_WD
pwd
}

_task6_sigint(){
# Here to just ignore SIGINT so doing nothing
}

task6(){
if [ $(docker ps | wc -l) -gt "1" ]; then
cat << EOF
Shutdown the running docker container first before you continue.
Use the command "docker ps" to get container name, then 
"docker stop <containter name>" to stop it.

We need port 8080 to be opened.
EOF
fi
cat << EOF
Task 6 - Create a pipeline in Jenkins to deploy your app
EOF
pause

# Preparing to connect to Jenkins
PASS=$(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)
POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/component=jenkins-master" -l "app.kubernetes.io/instance=cd" -o jsonpath="{.items[0].metadata.name}")
splitter
echo "kubectl port-forward $POD_NAME 8080:8080 >> /dev/null &"
kubectl port-forward $POD_NAME 8080:8080 >> /dev/null &
PROXY_PID=$!
echo "Forwarding process (PID: $PROXY_PID) started"

# Setup Jenkins
splitter
cat << EOF
Follow these steps:
1) Open the Jenkins console.
    Your credential:
        Username: admin
        Password: $PASS
2) Setup credentials
3) Create a job that points to the source repository (https://source.developers.google.com/p/$PROJECT/r/valkyrie-app)

Press enter when finished.
EOF
trap _task6_sigint SIGINT
pause
trap - SIGINT

splitter
ORIG_WD=$(pwd)
echo "Changing directory into valkyrie-app"
cd valkyrie-app
pwd

# Making changes in source file on master branch
cat << EOF
Change the placeholder "YOUR_PROJECT" to "$PROJECT" in Jenkinsfile
EOF
pause
echo_cmd $EDITOR Jenkinsfile
while [ $(grep "$PROJECT" Jenkinsfile | wc -l) -eq "0" ]; do
    echo "$PROJECT is not found in the Jenkinsfile, try again."
    pause
    echo_cmd $EDITOR Jenkinsfile
done
cat << EOF
Change all occurances of "green" to "orange" in html.go
EOF
pause
echo_cmd $EDITOR source/html.go
while [ $(grep green source/html.go | wc -l) -gt "0" ]; do
    echo "There is/are still occurance(s) in the html.go, try again."
    pause
    echo_cmd $EDITOR source/html.go
done

# Setup Git global config
echo_cmd "git config --global user.email '$ACCOUNT'"
USERNAME=$(echo $ACCOUNT | sed "s/@.*$//")
echo_cmd "git config --global user.name '$USERNAME'"

# Commit the changes and push to the remote repository
echo_cmd git add Jenkinsfile source/html.go Dockerfile
echo_cmd 'git commit -m "project ID in Jenkins file, green are now orange in html.go"'
echo_cmd git push origin master

splitter
cat << EOF
Check the Jenkins UI for build status.
EOF
pause

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

