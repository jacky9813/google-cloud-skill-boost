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

VPC_NAME=dm-stamford
REGION=us-west4

task1(){
cat << EOF
Task 1 - Prepare the environment (Creating VPC and subnets)
$(splitter)
In this task, we'll be creating a VPC ($VPC_NAME) with 2 subnets ($VPC_NAME-uswest4, $VPC_NAME-uswest4-ids) in us-east4 region.
EOF
pause
echo_cmd gcloud compute networks create $VPC_NAME --subnet-mode=custom
echo_cmd gcloud compute networks subnets create $VPC_NAME-uswest4 --region=$REGION --network=$VPC_NAME --range=172.21.0.0/24
echo_cmd gcloud compute networks subnets create $VPC_NAME-uswest4-ids --region=$REGION --network=$VPC_NAME --range=172.21.1.0/24
checkpoint
} # End of task 1

task2(){
cat << EOF
Task 2 - Creating firewall rules
$(splitter)
In this task, we'll create 3 firewall rules:
fw-$VPC_NAME-allow-any-web:
    ALLOW 80/tcp,icmp INGRESS from 0.0.0.0/0 to VPC $VPC_NAME
fw-$VPC_NAME-ids-any-any:
    ALLOW all_protocols INGRESS from 0.0.0.0/0 to VPC $VPC_NAME
fw-$VPC_NAME-iapproxy:
    ALLOW 22/tcp,icmp INGRESS from GoogleIAPRange(35.235.240.0/20) to $VPC_NAME
EOF
pause
echo_cmd gcloud compute firewall-rules create fw-$VPC_NAME-allow-any-web --direction=INGRESS --priority=1000 --network=$VPC_NAME --action=ALLOW --rules=tcp:80,icmp --source-ranges=0.0.0.0/0
echo_cmd gcloud compute firewall-rules create fw-$VPC_NAME-ids-any-any --direction=INGRESS --priority=1000 --network=$VPC_NAME --action=ALLOW --rules=all --source-ranges=0.0.0.0/0 --target-tags=ids
echo_cmd gcloud compute firewall-rules create fw-$VPC_NAME-iapproxy --direction=INGRESS --priority=1000 --network=$VPC_NAME --action=ALLOW --rules=tcp:22,icmp --source-ranges=35.235.240.0/20
checkpoint
} # End of task 2

task3(){
cat << EOF
Task 3 - Configuring router (Cloud router, Cloud NAT)
$(splitter)
Cloud NAT provides Internet access for whole VPC with only 1 public IP.

The IDS we'll create later on will not have public IP for security reason, but still need Internet access for updates and installations.
EOF
pause
echo_cmd gcloud compute routers create router-stamford-nat-west4 --network=$VPC_NAME --region=$REGION
echo_cmd gcloud compute routers nats create nat-gw-$VPC_NAME-west4 --router=router-stamford-nat-west4 --router-region=$REGION --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges
checkpoint
} # End of task 3

task4(){
cat << EOF
Task 4 - Create Virtual Machines
$(splitter)
In this task, we'll be creating the followings:
* Instance Template
    - template-$VPC_NAME-web-$REGION
        Image: Ubuntu 16.04
        Installed Packages: Apache HTTP Server (apache2)
        Tags: webserver
        Machine Type: g1-small
        Region: $REGION
        Network: $VPC_NAME
        Subnet: $VPC_NAME-uswest4
        External IP: Auto
    - template-$VPC_NAME-ids-$REGION
        Image: Ubuntu 16.04
        Installed Packages: Apache HTTP Server (apache2), Suricata
        Tags: ids,webserver
        Machine Type: (Not specified)
        Region: $REGION
        Internal Network: $VPC_NAME
        Subnet: $VPC_NAME-uswest4-ids
        External IP: (Disabled)
* Managed Instance Group
    - mig-$VPC_NAME-web-uswest4
        Template: template-$VPC_NAME-web-us-west4
        Size: 2
        Zone: $REGION-a
    - mig-$VPC_NAME-ids-uswest4
        Template: template-$VPC_NAME-ids-us-west4
        Size: 1
        Zone: $REGION-a
EOF
pause
splitter
cat << EOF
gcloud compute instance-templates create template-$VPC_NAME-web-$REGION \
--region=$REGION \
--network=$VPC_NAME \
--subnet=$VPC_NAME-uswest4 \
--machine-type=g1-small \
--image=ubuntu-1604-xenial-v20200807 \
--image-project=ubuntu-os-cloud \
--tags=webserver \
--metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install apache2 -y
  vm_hostname="\$(curl -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/name)"
  echo "Page served from: \$vm_hostname" | \
  tee /var/www/html/index.html
  systemctl restart apache2'
EOF
gcloud compute instance-templates create template-$VPC_NAME-web-$REGION \
--region=$REGION \
--network=$VPC_NAME \
--subnet=$VPC_NAME-uswest4 \
--machine-type=g1-small \
--image=ubuntu-1604-xenial-v20200807 \
--image-project=ubuntu-os-cloud \
--tags=webserver \
--metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install apache2 -y
  vm_hostname="$(curl -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/name)"
  echo "Page served from: $vm_hostname" | \
  tee /var/www/html/index.html
  systemctl restart apache2'

echo_cmd gcloud compute instance-groups managed create mig-$VPC_NAME-web-uswest4 --template=template-$VPC_NAME-web-$REGION --size=2 --zone=$REGION-a


splitter
cat << EOF
gcloud compute instance-templates create template-$VPC_NAME-ids-$REGION \
--region=$REGION \
--network=$VPC_NAME \
--no-address \
--subnet=$VPC_NAME-uswest4-ids \
--image=ubuntu-1604-xenial-v20200807 \
--image-project=ubuntu-os-cloud \
--tags=ids,webserver \
--metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install apache2 -y
  vm_hostname="\$(curl -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/name)"
  echo "Page served from: \$vm_hostname" | \
  tee /var/www/html/index.html
  systemctl restart apache2'
EOF
gcloud compute instance-templates create template-$VPC_NAME-ids-$REGION \
--region=$REGION \
--network=$VPC_NAME \
--no-address \
--subnet=$VPC_NAME-uswest4-ids \
--image=ubuntu-1604-xenial-v20200807 \
--image-project=ubuntu-os-cloud \
--tags=ids,webserver \
--metadata=startup-script='#! /bin/bash
  apt-get update
  apt-get install apache2 -y
  vm_hostname="$(curl -H "Metadata-Flavor:Google" \
  http://169.254.169.254/computeMetadata/v1/instance/name)"
  echo "Page served from: $vm_hostname" | \
  tee /var/www/html/index.html
  systemctl restart apache2'

echo_cmd gcloud compute instance-groups managed create mig-$VPC_NAME-ids-uswest4 --template=template-$VPC_NAME-ids-$REGION --size=1 --zone=$REGION-a

checkpoint
} # End of task 4

task5(){
cat << EOF
Task 5 - Create an Internal Load Balancer (ILB)
$(splitter)
The collector (IDS) uses ILB to forward packets to IDS instance groups.
In this task, we'll demonstrate the process of creating ILB for the collector.

Things to be created:
* Health checks
    - hc-tcp-80
        Type: TCP
        Port: 80/tcp
* Backend Service
    - be-$VPC_NAME-suricata-$REGION
        Scheme: internal
        Health Checker: hc-tcp-80
        Network: $VPC_NAME
        Region: $REGION
        Protocol: TCP
        Backends:
            - Name: mig-$VPC_NAME-ids-uswest4
              Zone: $RESION-a
              Region: $REGION
* Forwarding Rule
    - ilb-$VPC_NAME-suricata-ilb-$REGION
        Scheme: internal
        Backend service: be-$VPC_NAME-suricata-$REGION
        Is mirroring collector: True
        Network: $VPC_NAME
        Subnet: $VPC_NAME-uswest4-ids
        Region: $REGION
        Protocol: TCP (will be overwritten in the future task)
        Ports: all

EOF
pause
echo_cmd gcloud compute health-checks create tcp hc-tcp-80 --port 80
echo_cmd gcloud compute backend-services create be-$VPC_NAME-suricata-$REGION --load-balancing-scheme=INTERNAL --health-checks=hc-tcp-80 --network=$VPC_NAME --protocol=TCP --region=$REGION
echo_cmd gcloud compute backend-services add-backend be-$VPC_NAME-suricata-$REGION --instance-group=mig-$VPC_NAME-ids-uswest4 --instance-group-zone=$REGION-a --region=$REGION
echo_cmd gcloud compute forwarding-rules create ilb-$VPC_NAME-suricata-ilb-$REGION --load-balancing-scheme=INTERNAL --backend-service=be-$VPC_NAME-suricata-$REGION --is-mirroring-collector --network=$VPC_NAME --region=$REGION --subnet=$VPC_NAME-uswest4-ids --ip-protocol=TCP --ports=all

checkpoint
} # End of task 5

task6(){
IDS_INST_NAME=$(gcloud compute instance-groups managed list-instances mig-$VPC_NAME-ids-uswest4 --zone=$REGION-a  --format="csv(NAME)" --limit=1 | tail -n +2)
cat << EOF
Task 6 - Install Suricata IDS and configure packet mirroring policy
$(splitter)
In this task, we'll install Suricata and some custom rules into the IDS instance using the scripts inside.
EOF
pause

cat << EOF > echo-cmd.sh
#!/bin/bash
splitter(){
    i=\$(tput cols 2>/dev/null)
    tf=\$([ \$i == "" ] && echo 1 || echo "")
    i=\${i:-40}
    while [ \$i -gt "0" ]; do
        echo -n =
        i=\$((\$i - 1))
    done
    if [ \$tf ]; then
        echo ""
    fi
}
pause(){
    read -p "Press Enter to continue"
}
echo_cmd(){
    splitter
        echo \$@
        eval \$@
    RET=\$?
    if [ \$RET -ne "0" ]; then
        echo "Error occured! You can ignore this message and press enter to continue."
        pause
    fi
}
EOF
cat << EOF > install-suricata.sh
#!/bin/bash
source ~/echo-cmd.sh
echo_cmd sudo apt update
echo_cmd sudo apt install -y libpcre3-dbg libpcre3-dev autoconf automake libtool libpcap-dev libnet1-dev libyaml-dev zlib1g-dev libcap-ng-dev libmagic-dev libjansson-dev libjansson4 libnspr4-dev libnss3-dev liblz4-dev rustc cargo
echo_cmd sudo add-apt-repository ppa:oisf/suricata-stable -y
echo_cmd sudo apt update
echo_cmd sudo apt install -y suricata
echo_cmd suricata -V
EOF
cat << EOF > update-suricata-rules.sh
#!/bin/bash
source ~/echo-cmd.sh
echo_cmd sudo systemctl stop suricata
echo_cmd sudo cp /etc/suricata/suricata.yaml /etc/suricata/suricata.backup
echo_cmd sudo mkdir -p /etc/suricata/poc-rules
echo_cmd sudo wget -O /etc/suricata/suricata.yaml https://storage.googleapis.com/tech-academy-enablement/GCP-Packet-Mirroring-with-OpenSource-IDS/suricata.yaml
echo_cmd sudo wget -O /etc/suricata/poc-rules/my.rules https://storage.googleapis.com/tech-academy-enablement/GCP-Packet-Mirroring-with-OpenSource-IDS/my.rules
echo_cmd sudo systemctl restart suricata
EOF
chmod +x install-suricata.sh update-suricata-rules.sh echo-cmd.sh

# Uploading scripts
gcloud compute scp --zone=$REGION-a echo-cmd.sh install-suricata.sh update-suricata-rules.sh $IDS_INST_NAME:~

# Fetching the name of the IDS instance
splitter
echo "Switching context to $IDS_INST_NAME..."
gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --command='~/install-suricata.sh'
gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --command='~/update-suricata-rules.sh'

splitter
echo "Switching back to cloud shell..."

splitter
echo "Creating Packet Mirroring Policy"
echo_cmd gcloud compute packet-mirrorings create mirror-$VPC_NAME-web --collector-ilb=ilb-$VPC_NAME-suricata-ilb-$REGION --network=$VPC_NAME --mirrored-subnets=$VPC_NAME-uswest4 --region=$REGION
} # End of task 6

task7(){
IDS_INST_NAME=$(gcloud compute instance-groups managed list-instances mig-$VPC_NAME-ids-uswest4 --zone=$REGION-a --format="csv(NAME)" --limit=1 | tail -n +2)
cat << EOF
Task 7 - Test packet mirroring
$(splitter)
We'll test if we've configured packet mirroring correctly.
Here's the list of target instances:
$(gcloud compute instances list --filter="name:mig-$VPC_NAME-web-uswest4*" --zones=$REGION-a --format='table(NAME, EXTERNAL_IP)')

Launch another cloud shell to ping, send HTTP request to those IPs.

Use the following shell to execute this command:
    sudo tcpdump -i ens4 -nn -n "(icmp or port 80) and net 172.21.0.0/24"
Click Ctrl-C to end the tcpdump output.
EOF
pause

splitter
# Cloud shell doesn't come with ping for some reason...
echo "Installing Ping utility if not installed..."
sudo apt install iputils-ping

# For unknown reason, pass the command using --command flag cannot output the result properly.

echo_cmd gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a
} # End of task 7

task8(){
WEB_INST_NAME=$(gcloud compute instance-groups managed list-instances mig-$VPC_NAME-web-uswest4 --zone=$REGION-a --format="csv(NAME)" --limit=1 | tail -n +2)
WEB_INST_EXT_IP=$(gcloud compute instances list --filter="name:$WEB_INST_NAME" --zones=$REGION-a --format="csv(EXTERNAL_IP)" | tail -n +2)
IDS_INST_NAME=$(gcloud compute instance-groups managed list-instances mig-$VPC_NAME-ids-uswest4 --zone=$REGION-a  --format="csv(NAME)" --limit=1 | tail -n +2)
cat << EOF
Task 8 - Test IDS rules
$(splitter)
We'll test IDS rules from both one of the web servers and cloud shell. Here's the details of each test:
* TEST 1
    Instance: web server ($WEB_INST_NAME)
    Direction: EGRESS
    Description: Sending DNS request asking 8.8.8.8 about example.com
* TEST 2
    Instance: web server ($WEB_INST_NAME)
    Direction: EGRESS
    Description: Attempt to connect to 100.64.1.1:6667 using nc (netcat)
                (telnet has no connection timeout settings)
* TEST 3
    Instance: cloud shell
    Direction: INGRESS
    Desctiption: Attempt ping the web servers
* TEST 4
    Instance: cloud shell
    Direction: INGRESS
    Description: Accessing /index.php from one of the web servers.
EOF
pause

splitter
echo "**** TEST 1 ****"
# gcloud SSH will attempt using external IP if existed.
# But dm-stamford never opened 22/tcp to the public, it won't work unless tunnel through IAP or using internal IP.
echo_cmd "gcloud compute ssh $WEB_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='dig @8.8.8.8 example.com'"
echo_cmd "gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='egrep \"BAD UDP DNS\" /var/log/suricata/eve.json'"

splitter
echo "**** TEST 2 ****"
echo_cmd "gcloud compute ssh $WEB_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='nc -w 10 100.64.1.1 6667;exit 0'"
echo_cmd "gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='egrep \"BAD TCP\" /var/log/suricata/eve.json'"

splitter
echo "**** TEST 3 ****"
echo_cmd ping -c 3 $WEB_INST_EXT_IP
echo_cmd "gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='egrep \"BAD ICMP\" /var/log/suricata/eve.json'"

splitter
echo "**** TEST 4 ****"
echo_cmd curl http://$WEB_INST_EXT_IP/index.php
echo_cmd "gcloud compute ssh $IDS_INST_NAME --zone=$REGION-a --tunnel-through-iap --command='egrep \"BAD HTTP\" /var/log/suricata/eve.json'"
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

