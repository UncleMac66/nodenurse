#!/bin/bash

# Check if an argument is passed
if [ -z "$1" ]; then
    echo " "
    echo -e "Usage: $0 | -h [Run fresh healthchecks on node(s)] | -l [Get the latest healthcheck from the node(s)] | -r [Hard reset node(s)] | -i [Identify nodes] | <hostname, hostfile, or leave blank to pull down hosts from sinfo>"
    echo ""
    echo "$0 takes the nodes that are in a down/drain state in slurm or a supplied nodename or hostfile and can run a fresh healthcheck on them, grab the latest healthcheck, send them through ncclscout.py, or can be used to initiate a hard reboot of those nodes."
    echo " " 
    echo "Syntax: $0 [option] [host or hostfile]"
    echo " " 
    echo "For example:"
    echo "$0 -h <path/to/hostfile> -> runs a fresh healthcheck on the node(s) in the provided hostlist"
    echo " "
    echo "$0 -r gpu-123 -> sends a hard reboot signal to node 'gpu-123'"
    echo " "
    echo -e "$0 -l -> grabs the latest healthchecks from nodes marked as drain or down in slurm"
    echo " " 
    exit 1
fi

# Check first argument to grab function or exit if no valid option is provided
if [[ $1 == "-h" ]] || [[ $1 == "-f" ]]; then
    ntype=healthfresh
elif [[ $1 == "-l" ]] || [[ $1 == "-hl" ]]; then
    ntype=healthlatest
elif [[ $1 == "-r" ]]; then
    ntype=rebootall
elif [[ $1 == "-i" ]]; then
    ntype=idnodes
else
    echo "Unknown argument. Please try again"
    exit 1
fi

# If a second argument is passed, assume its a nodename or a hostfile. If no second argument is passed grab the list of nodes in a down state in slurm
if [ -f "$2" ]; then
    # arg is a hostfile
    echo " "
    echo "Reading from provided hostfile..."
    echo " " 
    for i in $(cat "$2")
    do
      nodes+="$i "
    done
elif [ -z "$2" ]; then
    # no argument provided so pull from sinfo
    echo " "
    echo "No hostfile provided. Grabbing down/drain hosts from slurm..."
    echo " " 
    nodes=$(sinfo -N | grep -E "down|drain" | awk '{print $1}' | sort -u)
else
    # arg is a single hostname
    echo " "
    echo "Single hostname provided..."
    echo " " 
    nodes="$2"
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
numnodes=$(echo $nodes | wc -w) 
allocstate=false
parallel=false
goodhealth=true

# Function takes in a hostname (e.g. gpu-123) and returns it's instance name in the OCI console
generate_instance_name() {
    inst=`cat /etc/hosts | grep "$1 " | grep .local.vcn | awk '{print $4}'`
    echo $inst
}

# Function takes in an instance name and returns it's OCID
generate_ocid() {
    outputocid=`oci compute instance list --compartment-id $compartmentid --display-name $1 --auth instance_principal | jq -r .data[0].id`
    echo $outputocid
}

generate_slurm_state() {
    outputstate=`sinfo -N | grep "$1 " | awk '{print $4}' | sort -u` 
    echo $outputstate
}

generate_serial() {
    outputserial=`ssh $1 "sudo dmidecode -s system-serial-number"`
    echo $outputserial
}

# Function displays the list of 'Down/drain Hosts' along with with instance names and OCIDs
display_nodes() {
    
    echo "----------------------------------------------------------------"
    echo "----------------------" $start_timestamp "---------------------"
    echo "----------------------------------------------------------------"
    echo " " 
    printf "%-10s %-25s %-15s %-10s\n" "Hostname" "Instance Name" "Host Serial #" "Slurm State"
    echo " " 
    if [ -z "$nodes" ];then
      echo "There are no hosts that are showing as down/drain in sinfo"
      echo " "
      echo "exiting..."
      exit 0
    fi

    # Loop through each node and get its instance name and details
    for n in $nodes
    do
      inst=`generate_instance_name $n`
      state=`generate_slurm_state $n`
      serial=`generate_serial $n`
      if [[ $state =~ "mix" ]] || [[ $state =~ "alloc" ]]; then
        allocstate=true
      fi
      printf "%-10s %-25s %-15s %-10s\n" "$n" "$inst" "$serial" "$state"
      echo " "
    done	

    # Display total num of nodes
    echo "Total: $numnodes Host(s)"
    echo " "

    # if any nodes are in alloc state then warn user
    if [[ $allocstate == true ]]; then
      echo -e "${RED}WARNING:${NC} There are hosts in an allocated state. Proceed with caution as rebooting nodes that are running jobs is ill-advised and can cause significant customer disruption" 
      echo " "
    fi

    if [[ $ntype == idnodes ]]; then 
      exit 0
    fi

        echo " " 
}

if [ $ntype == idnodes ]; then

    display_nodes

fi

if [[ $ntype == healthfresh ]] || [[ $ntype == healthlatest ]]; then

    currentnumnodes=1
    display_nodes
    echo "Do you want to run healthchecks in parallel? (yes/no)"
    read response
    case $response in 
      yes|YES|Yes|y|Y)
        parallel=true
      ;;
      no|NO|No|n|N)
        parallel=false
      ;;	
      *)
        echo "Invalid input. Please enter yes or no."
      ;;
    esac

    if [[ $parallel == false ]]; then
      # Loop through each node and grab the healthcheck
      for n in $nodes
      do
        echo " " 
        echo "----------------------------------------------------------------" 
        echo -e "Healthcheck from node: ${YELLOW}$n${NC} -- Node $currentnumnodes/$numnodes"
        echo "----------------------------------------------------------------" 
        if [[ $ntype == healthfresh ]]; then
          ssh "$n" "sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py" || echo "Failed to connect to $n"
        else
          ssh "$n" "cat /tmp/latest_healthcheck.log" || echo "Can't find the latest healthcheck. Are healthchecks enabled on this cluster?"
        fi
        echo " " 
        let currentnumnodes++
      done
    else
      # run healthchecks in parallel
      echo " " 
      echo "----------------------------------------------------------------" 
      echo "Healthchecks from nodes: $nodes"
      echo " " 
      echo "Note: To simplify output only reporting warnings and errors"
      echo "----------------------------------------------------------------" 
      echo " " 
      if [[ $ntype == healthfresh ]]; then
        pdsh -R ssh -w "$nodes" "sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py -l ERROR -l WARNING" || echo -e \n"Failed to gather healthchecks in parallel" 
	echo " " 
      else
        pdsh -R ssh -u 5 -w "$nodes" "cat /tmp/latest_healthcheck.log | grep -E "ERROR|WARNING"" || {echo -e "\nCan't find the latest healthcheck. Are healthchecks enabled on this cluster?" && goodhealth=false}
      echo " " 
      fi
    fi

#    if [[ $goodhealth == "true" ]]; then
      echo -e "${GREEN}Complete:${NC} Healthchecks gathered on $numnodes nodes"
      echo " " 
      echo $goodhealth
#    else
#      echo -e "$(RED}Completed with errors:${NC} Healthchecks gathering on $numnodes completed with errors"
#    fi


    # Offer to run ncclscout if number of node is greater than 1
    if [ $numnodes -gt 1 ];then
      echo "Would you like to run ncclscout on these $numnodes nodes? (yes/no)"
      read response
      echo " "
      case $response in
        yes|Yes|YES|y|Y)
          echo "Proceeding..."
          echo " "
	  for i in $nodes
	  do
	    echo $i >> $date-hostfile.tmp
	  done
	  python3 ncclscout.py $date-hostfile.tmp
	  rm $date-hostfile.tmp
	  echo " "
        ;;
        no|No|NO|n|N)
      	exit 1
        ;;
        *)
          echo "Invalid input. Please enter yes or no."
        ;;
      esac
    fi

fi

if [ $ntype == rebootall ]; then

    display_nodes

    # ask for confirmation before reboot
    echo -e "Are you sure you want to hard reboot these nodes? (yes/no)"
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
	    echo -e "$(date) - ${GREEN}Success${NC} - Hard reset command sent to node ${YELLOW}$n${NC}" | tee -a $date-nodenurse.log
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

