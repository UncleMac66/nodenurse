#!/bin/bash

# Check if an argument is passed
if [ -z "$1" ]; then
    echo "Usage: $0 healthcheck | reboot | <host or leave blank to pull down hosts from sinfo>"
    echo ""
    echo "$0 takes the nodes that are in a down state in slurm or a supplied nodename and either runs a fresh healthcheck on them or can be used to initiate a hard reboot of those nodes"
    exit 1
fi

# Check first argument to grab function or exit if no valid option is provided
if [[ $1 == "healthcheck" || $1 == "health" || $1 == "-h" || $1 == "h" ]]; 
   then
      ntype=healthonly
   elif [[ $1 == "reboot" || $1 == "-r" || $1 == "r" ]]; 
   then
      ntype=rebootall
   else
      echo "Unknown argument. Please try again"
      exit 1
fi

# If a second argument is passed, assume its a nodename or a hostfile. If no second argument is passed grab the list of nodes in a down state in slurm
if [ -n "$2" ]; then
   nodes="$2"
   else
   nodes=$(sinfo -N | grep down | awk '{print $1}' | sort -u)
fi

# Initialize colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Initialize Dates
date=`date -u '+%Y%m%d%H%M'`
start_timestamp=`date -u +'%F %T'`

# Initialize global variables
compartmentid=$(cat /opt/oci-hpc/conf/queues.conf | grep targetCompartment: | sort -u | awk '{print $2}')
reboot=true

# Function takes in a hostname (e.g. gpu-123) and returns it's instance name in the OCI console
generate_instance_name() {
	inst=`cat /etc/hosts | grep "$1 " | grep .local.vcn | awk '{print $4}'`
	echo $inst
}

# Function takes in an instance name and returns it's OCID
generate_ocid() {
	inputocid=`oci compute instance list --compartment-id $compartmentid --display-name $1 --auth instance_principal | jq -r .data[0].id`
	echo $inputocid
}

# Function displays the list of 'Down Hosts' along with with instance names and OCIDs
display_nodes() {
    echo "----------------------" $start_timestamp "---------------------"
    echo "----------------------------------------------------------------"
    echo -e "Down Hosts:"
    echo " " 
    if [ -z "$nodes" ];then
      echo "There are no hosts that are showing as down in sinfo"
      echo "exiting..."
      exit 1
    fi
    # Loop through each node and get it's instance name
    for n in $nodes
    do
	inst=`generate_instance_name $n`
	ocid=`generate_ocid $inst`
	echo -e " ${RED}$n${NC} <-> $inst <-> $ocid"
	echo " "
    done	
}


if [ $ntype == healthonly ]; then

    display_nodes

    # Loop through each node and grab the healthcheck
    for n in $nodes
    do
        echo "----------------------------------------------------------------" 
        echo -e "Healthcheck from node: ${RED}$n${NC} "
        echo "----------------------------------------------------------------" 
	ssh "$n" "sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py" || echo "Failed to connect to $n"
	echo " " 
    done
fi

if [ $ntype == rebootall ]; then

    display_nodes

    # ask for confirmation before reboot
    echo "Are you sure you want to hard reboot these nodes? (yes/no)"
    read response
    echo " " 
    case $response in

      yes|Yes|YES|y|Y)
        echo "Proceeding..."
	echo " "         
	for n in $nodes
	do
	  echo "----------------------------------------------------------------"	
          inst=`generate_instance_name $n`
          ocid=`generate_ocid $inst`
          echo -e "Rebooting ${YELLOW}$n${NC}"
	  echo -e "Instance Name: $inst"
	  echo -e "OCID: $ocid"
	  echo " " 
          oci compute instance action --instance-id $ocid --action RESET --auth instance_principal >> $date-nodenurse.log || reboot=false	
	  if [ $reboot == false ];
	  then
            echo " "
            echo -e "${RED}Reset command failed!${NC}" 
	    echo " "
	  else 
	    echo -e "$date - ${GREEN}Success${NC} - Hard reset command sent to node ${YELLOW}$n${NC}"
	  fi
	  echo "----------------------------------------------------------------"
	  echo " "
        done
        ;;

      no|No|NO|n|N)
        echo "Aborting..."
        exit 1
        ;;

      *)
        echo "Invalid input. Please enter yes or no."
        ;;
    esac
fi

