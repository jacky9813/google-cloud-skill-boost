#!/bin/bash

NO_PAUSE={$NO_PAUSE:-false}

pause(){
if ! $NO_PAUSE; then
        read -n 1 -p "Press Enter to continue..." INP
        if [ "" != "" ]; then
                echo -ne "\b \n"
        fi
fi
}

# ==================== Task 1 ====================
task1(){
echo "Setting up gcloud CLI"
gcloud config set compute/zone us-central1-a
gcloud config set compute/region us-central1
}

# ==================== Task 2 ====================
task2(){
echo "Creating 3 instances with slightly different content."
for i in 1 2 3; do
	echo "Creating www$i..."
	gcloud compute instances create www$i \
		--image-family=debian-9 \
		--image-project=debian-cloud \
		--zone=us-central1-a \
		--tags=network-lb-tag \
		--metadata=startup-script="#!/bin/bash
	sudo apt update
	sudo apt install -y apache2
	sudo service apache2 restart
	echo '<!DOCTYPE html><html><body><h1>www$i</h1></body></html>' | tee /var/www/html/index.html"
done
gcloud compute firewall-rules create www-firewall-network-lb --target-tags=network-lb-tag --allow=tcp:80
echo "Wait 10 seconds for system booting up..."
sleep 10
echo "Checking if all instances are able to provide service"
gcloud compute instances list | grep EXTERNAL_IP | sed "s/^[^1-9]*/curl http\:\/\//g" | bash
pause
}

# ==================== Task 3 ====================
task3(){
cat << EOF
Task 3 mainly focus on 
* Creating a basic load balancer
* Enabling HTTP health check called "basic-check"
* Putting all instances in pool "www-pool"
* Creating an IP that forward request to all instances, specified in "www-rule"
EOF
gcloud compute addresses create network-lb-ip-1 --region=us-central1
gcloud compute http-health-checks create basic-check
gcloud compute target-pools create www-pool --region=us-central1 --http-health-check=basic-check
gcloud compute target-pools add-instances www-pool --instances=www1,www2,www3
gcloud compute forwarding-rules create www-rule --region us-central1 --ports 80 --address network-lb-ip-1 --target-pool www-pool
pause
}

# ==================== Task 4 ====================
task4(){
IP_ADDRESS=$(gcloud compute forwarding-rules describe www-rule --region=us-central1 | grep IPAddress | sed "s/^[^1-9]*//")
cat << EOF
Fetching $IP_ADDRESS
Ctrl-C to stop.
EOF
while true; do
	curl -m1 $IP_ADDRESS
	sleep 1
done
}

# ==================== Task 5 ====================
task5(){
echo "Creating template"
export TEMPLATE=lb-backend-template
export TAG=allow-health-check
gcloud compute instance-templates create $TEMPLATE \
        --region=us-central1 \
        --network=default \
        --subnet=default \
        --tags=$TAG \
        --image-family=debian-9 \
        --image-project=debian-cloud \
        --metadata=startup-script='#!/bin/bash
apt update && apt install -y apache2
a2ensite default-ssl
a2enmod ssl
vm_hostname="$(curl -H "Metadata-Flavor:Google" http://169.254.169.254/computeMetadata/v1/instance/name)"
echo "Page served from: $vm_hostname" | tee /var/www/html/index.html
systemctl restart apache2
'
pause

echo "Creating instance group with 2 instances based off the template"
export INST_GRP=lb-backend-group
gcloud compute instance-groups managed create $INST_GRP --template=$TEMPLATE --size=2 --zone=us-central1-a
pause

echo "Creating firewall rules"
export FW_HEALTH_RULE=fw-allow-health-check
gcloud compute firewall-rules create $FW_HEALTH_RULE --network=default --action=allow --direction=ingress --source-ranges=130.211.0.0/22,35.191.0.0/16 --target-tags=$TAG --rules=tcp:80
pause

echo "Retrieve a global IP address"
export GLOBAL_IP=lb-ipv4-1
gcloud compute addresses create $GLOBAL_IP --ip-version=IPV4 --global
gcloud compute addresses describe $GLOBAL_IP --format="get(address)" --global
pause

echo "implementing health check for load balancer"
export HEALTH_CHECKER=http-basic-check
gcloud compute health-checks create http $HEALTH_CHECKER --port 80
pause

echo "Creating backend service"
export BACKEND_SERVICE=web-backend-service
gcloud compute backend-services create $BACKEND_SERVICE --protocol=HTTP --port-name=http --health-checks=$HEALTH_CHECKER --global
pause

echo "Adding instances into the backend service"
gcloud compute backend-services add-backend $BACKEND_SERVICE --instance-group=$INST_GRP --instance-group-zone=us-central1-a --global
pause

echo "Creating a URL map"
export MAP=web-map-http
gcloud compute url-maps create $MAP --default-service $BACKEND_SERVICE
pause

echo "Creating target HTTP proxy"
export PROXY=http-lb-proxy
gcloud compute target-http-proxies create $PROXY --url-map $MAP
pause

echo "Creating forwarding rules"
FWD_RULE=http-content-rule
gcloud compute forwarding-rules create $FWD_RULE --address=$GLOBAL_IP --global --target-http-proxy=$PROXY --ports=80
pause
}

# ==================== Task 6 ====================
task6(){
GLOBAL_IP=lb-ipv4-1
IP_ADDRESS=$(gcloud compute addresses describe $GLOBAL_IP --format="get(address)" --global)
while true; do
	curl -m1 $IP_ADDRESS
	sleep 1
done
}

[[ $(type -t task$1) == function ]] && task$1
