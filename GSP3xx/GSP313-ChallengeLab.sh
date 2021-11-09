#!/bin/bash

# TODO
# gcloud config get-value compute/zone
# gcloud config get-value compute/region
DEF_ZONE=us-east1-b
DEF_REGION=us-east1

task1(){
echo "Task 1 - Create a jumphost instance"
if [ "$2" == "" ] ;then
echo "Usage: $0 $1 <Instance Name>"
else
gcloud compute instances create $2 --machine-type=f1-micro --zone=$DEF_ZONE --region=$DEF_REGION
fi
}

task2(){
echo "Task 2 - Create a Kubernetes service cluster"
if [ "$2" == "" ];then
echo "Usage: $0 $1 <Port number to open>"
else
CLUSTER=k8s-cluster
ZONE=us-east1-b
IMAGE=gcr.io/google-samples/hello-app:2.0
SRV_NAME=placeholder-container
MACHINE_TYPE=n1-standard-1
echo "Creating a kubernetes cluster named $CLUSTER using machine type $MACHINE_TYPE in zone $ZONE"
gcloud container clusters create $CLUSTER --zone=$ZONE --machine-type=$MACHINE_TYPE

echo "Getting kubernetes credentials from $CLUSTER"
gcloud container clusters get-credentials $CLUSTER --zone=$ZONE

echo "Deploying container image $IMAGE as a service named $SRV_NAME"
kubectl create deployment $SRV_NAME --image=$IMAGE

echo "Exposing $SRV_NAME to port $2"
kubectl expose deployment $SRV_NAME --type=LoadBalancer --port $2

kubectl get service
fi
}

task3(){
echo "Task 3 - Set up an HTTP load balancer"
if [ "$2" == "" ]; then
echo "Usage: $0 $1 <firewall rule name>"
else
echo "Creating an instance template"
TEMPLATE=nucleus-template
TAG=nucleus-http-tag
INSTANCE_GRP=nucleus-webserver
TARGET_POOL=nucleus-target-pool
FIREWALL_RULE=$2
LB_IP=nucleus-lb-address
HEALTH_CHK=nucleus-http-health-checker
BACKEND_SRV=nucleus-web-backend-service
MAP=nucleus-url-map-http
PROXY=nucleus-http-proxy
FWD_RULE=nucleus-forward-http-request
MACHINE_TYPE=f1-micro
STARTUP_SCRIPT=startup.sh

echo "Creating template \"$TEMPLATE\""
cat << EOF > $STARTUP_SCRIPT
#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- 's/nginx/Google Cloud Platform - '"\$HOSTNAME"'/' /var/www/html/index.nginx-debian.html
EOF
gcloud compute instance-templates create $TEMPLATE \
	--region=$DEF_REGION \
	--tags=$TAG \
	--network=default \
	--subnet=default \
	--machine-type=$MACHINE_TYPE \
	--metadata-from-file=startup-script=$STARTUP_SCRIPT
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating instance group"
gcloud compute instance-groups managed create $INSTANCE_GRP --template=$TEMPLATE --size=2 --zone=$DEF_ZONE
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating firewall rule"
gcloud compute firewall-rules create $FIREWALL_RULE --network=default --action=allow --direction=ingress --target-tags=$TAG --rules=tcp:80
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Requesting a global IP address"
gcloud compute addresses create $LB_IP --ip-version=IPV4 --global
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating health checker"
gcloud compute health-checks create http $HEALTH_CHK --port=80
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

#echo "Creating target pool"
#gcloud compute target-pools create $TARGET_POOL --health-check=$HEALTH_CHK
#TODO
#gcloud compute instance-groups list-instances $INSTANCE_GRP
#cat << EOF
#===================================================
#Use "gcloud compute target-pools add-instance --instance=<Instance 1>[,<Instance 2>...]" to add instances into target pool.
#===================================================
#EOF

echo "Creating backend service"
gcloud compute backend-services create $BACKEND_SRV --protocol=HTTP --port-name=http --health-checks=$HEALTH_CHK --global
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Adding instances into backend service"
gcloud compute backend-services add-backend $BACKEND_SRV --instance-group=$INSTANCE_GRP --global --instance-group-zone=$DEF_ZONE
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating URL map"
gcloud compute url-maps create $MAP --default-service=$BACKEND_SRV
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating target HTTP proxy"
gcloud compute target-http-proxies create $PROXY --url-map=$MAP
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi

echo "Creating forwarding rules"
gcloud compute forwarding-rules create $FWD_RULE --address=$LB_IP --global --target-http-proxy=$PROXY --ports=80
if [ "$?" -ne "0" ] ; then
read -p "Error occured. Press Enter to ignore"
fi
fi
}


[[ $(type -t task$1) == function ]] && task$1 $@ || echo "No task named task$1"
