#!/bin/bash

HELP_MESSAGE="
Usage: $0 [OPTION] [HOST(S)]

Description:
  nodenurse.sh takes the nodes that are in a down/drain state in slurm, supplied nodename(s), or a hostfile and 
  can run a fresh healthcheck on them, grab the latest healthcheck, send them through ncclscout.py, or can be used 
  to initiate a hard reboot of those nodes.

Options:
  -h, --help             Display this message and exit.
  -c, --healthcheck      Run a fresh healthcheck on the node(s).
  -l, --latest           Gather the latest healthcheck from the node(s).
  -t, --tagunhealthy     Apply the unhealthy tag to the node(s)
  -r, --reboot           Hard reboot the node(s).
  -i, --identify         Display detail of the node(s) and exit.

Arguments:
  HOST(S)                An input hostfile, or space separated list of hostnames (e.g. gpu-1 gpu-2).
                         This is optional. If no hosts are provided nodenurse will pull in nodes
                         that are in a down or drain state in slurm by default.

Examples:
  $0 -c <path/to/hostfile>    runs a fresh healthcheck on the node(s) in the provided hostlist.
  $0 -r gpu-1                 sends a hard reboot signal to node 'gpu-1'.
  $0 -l                       grabs the latest healthchecks from nodes marked as drain or down in slurm.
  $0 --identify gpu-1 gpu-2   display details about 'gpu-1' and 'gpu-2' then quit.

Notes:
  - nodenurse.sh gets the compartement OCID from /opt/oci-hpc/conf/queues.conf.
  If you use queues across compartments please double check this value and consider 
  hard-coding it to your use case.

  - In order for tagging hosts as unhealthy to work properly, your tenancy must be properly
  whitelisted for unhealthy instance tagging and have the correct tag namespace and tags set up.

  - nodenurse.sh automatically deduplicates your provided hostlist.

  - tagunhealthy.py must be present in same directory as nodenurse.sh for tagging to work
"

HELP_BRIEF="usage: $0 [-c healthcheck] [-l latest] [-r reboot]
                      [-i identify] [-t tagunhealthy] [-h help]
                      [OPTION {HOST(S)}]"

# Check if an argument is passed
if [ -z "$1" ]; then
    echo "$HELP_BRIEF"
    exit 1
fi

# Check first argument to grab function or exit if no valid option is provided
if [[ $1 == "-c" ]] || [[ $1 == "--healthcheck" ]]; then
    ntype=healthfresh
    echo -e "\nFresh Healthcheck Mode..."

elif [[ $1 == "-l" ]] || [[ $1 == "--latest" ]]; then
    ntype=healthlatest
    echo -e "\nLatest Healthcheck Mode..."

elif [[ $1 == "-r" ]] || [[ $1 == "--reboot" ]]; then
    ntype=rebootall
    echo -e "\nReboot Mode..."

elif [[ $1 == "-i" ]] || [[ $1 == "--identify" ]]; then
    ntype=idnodes
    echo -e "\nIdentify Mode..."

elif [[ $1 == "-t" ]] || [[ $1 == "--tagunhealthy" ]]; then
    ntype=tag
    echo -e "\nTagging Mode..."

elif [[ $1 == "-h" ]] || [[ $1 == "--help" ]]; then
    echo "$HELP_MESSAGE"
    exit 0

else
    echo "$HELP_BRIEF"
    echo -e "\nUnknown argument '$1' Please try again"
    exit 1

fi # End argument check

# Host/hostfile Input
# If a second argument is passed, assume its a nodename or a hostfile. If no second argument is passed grab the list of nodes in a down state in slurm
if [ -f "$2" ]; then

    # arg is a hostfile
    echo -e "\nReading from provided hostfile...\n"
    for i in $(cat "$2")
    do
      nodes+="$i "
    done

elif [ -z "$2" ]; then

    # no argument provided so pull from sinfo
    echo -e "\nNo hostfile provided. Grabbing down/drain hosts from slurm...\n"
    nodes=$(sinfo -N | grep -E "down|drain" | awk '{print $1}' | sort -u | tr '\n' ' ')

else

    # arg is/are manually entered hostname(s)
    for arg in "${@:2}"; do
      nodes+="$arg "
    done
    echo -e "\nHostname(s) provided manually...\n"

fi # End Host/hostfile input

# deduplicate nodelist
nodes=$(echo $nodes | tr " " "\n" | sort -u | tr "\n" " ")

# Initialize colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Initialize Dates
date=`date -u '+%Y%m%d%H%M'`
start_timestamp=`date -u +'%F %T'`

# Initialize logs
# Create logs folder if it doesn't exist
LOGS_FOLDER="logs"
if [ ! -d "$LOGS_FOLDER" ]; then
  mkdir -p "$LOGS_FOLDER"
fi
LOG_FILE=$date-nodenurse.log
LOG_PATH="$LOGS_FOLDER/$LOG_FILE"

# Initialize global variables
compartmentid=$(cat /opt/oci-hpc/conf/queues.conf | grep targetCompartment: | sort -u | awk '{print $2}')
reboot=true
goodtag=true
numnodes=$(echo $nodes | wc -w) 
allocstate=false
parallel=false
goodhealth=true
goodssh=true
goodinst=true
goodslurm=true

# Function takes in a hostname (e.g. gpu-123) and returns it's instance name in the OCI console
generate_instance_name() {
    inst=`cat /etc/hosts | grep "$1 " | grep .local.vcn | awk '{print $4}'`
    if [ -z $inst ]; then
      echo -e "Not Found"
    else
      echo $inst
    fi
}

# Function takes in an instance name and returns it's OCID
generate_ocid() {
    outputocid=`oci compute instance list --compartment-id $compartmentid --display-name $1 --auth instance_principal | jq -r .data[0].id || echo -e "${RED}Error:${NC} Could not retrieve instance OCID"`
    echo $outputocid
}

# Function takes in a hostname (e.g. gpu-123) and returns it's state in slurm
generate_slurm_state() {
    outputstate=`sinfo -N | grep "$1 " | awk '{print $4}' | sort -u`
    if [ -z $outputstate ]; then
      echo -e "Not Found"
    else
      echo $outputstate
    fi
}

# Function takes in a hostname (e.g. gpu-123) and returns it's serial number
generate_serial() {
    outputserial=`ssh $1 "sudo dmidecode -s system-serial-number" || echo -e "Error: SSH"`
    echo $outputserial
}

# Function displays the list of hosts along with relevant information, checking for nodes that can't be ssh'd or are in an allocated state in slurm
display_nodes() {

    echo "----------------------------------------------------------------"
    echo "----------------------" $start_timestamp "---------------------"
    echo "----------------------------------------------------------------"
    echo " " 
    printf "%-10s %-25s %-15s %-10s\n" "Hostname" "Instance Name" "Host Serial #" "Slurm State"
    echo " " 
    if [ `echo $nodes | wc -w` -eq 0 ];then
      echo -e "${YELLOW}Warning:${NC} No hosts to list. There are no hosts that are showing as down/drain in sinfo."

      echo " "
      echo "exiting..."
      exit 0
    fi

    # Loop through each node and get its instance name and details
    for n in $nodes
    do

      # Gather details
      inst=`generate_instance_name $n`
      state=`generate_slurm_state $n`
      serial=`generate_serial $n`
      
      # Node error checking
      if [[ $state =~ "mix" ]] || [[ $state =~ "alloc" ]]; then
        allocstate=true
      fi

      if [[ $serial == "Error: SSH" ]]; then
	goodssh=false
      fi

      if [[ $inst == "Not Found" ]]; then
	goodinst=false
      fi

      if [[ $state == "Not Found" ]]; then
	goodslurm=false
      fi

      # output node data
      printf "%-10s %-25s %-15s %-10s\n" "$n" "$inst" "$serial" "$state"
      echo " "
    done

    # Display total num of nodes
    echo "Total: $numnodes Host(s)"
    echo " "

    # if any nodes are in alloc state then warn user
    if [[ $allocstate == true ]]; then
      echo -e "${RED}WARNING:${NC} There are hosts in an allocated state."
      echo -e "Proceed with caution as rebooting nodes that are running jobs is ill-advised and can cause significant customer disruption\n"
    fi

    # If there is an ssh failure warn the user
    if [[ $goodssh == false ]]; then
      echo -e "${RED}WARNING:${NC} There are hosts that are inaccessible via SSH"
      echo -e "Healthchecks and ansible scripts will fail on these hosts.\n"
    fi

    # If instance name is not in /etc/hosts
    if [[ $goodinst == false ]] || [[ $goodslurm == false ]]; then
      echo -e "${RED}WARNING:${NC} There are hosts that can't be found in /etc/hosts or in slurm."
      echo -e "The host(s) may not exist, were mistyped, or were not correctly added to the cluster\n"
    fi

}

# Main Function for --identify
if [ $ntype == idnodes ]; then

    # Just display the node information and exit
    display_nodes
    exit 0

fi

# Main Function for --healthcheck and --latest
if [[ $ntype == healthfresh ]] || [[ $ntype == healthlatest ]]; then

    # Initialize the node count and display node details
    currentnumnodes=1
    display_nodes

    # Prompt user for parallelism if running fresh healthcheck and number of nodes is greater than 2 otherwise just run sequentially
    if [[ $numnodes -gt 2 ]] && [[ $ntype == healthfresh ]]; then
      echo "Do you want to run healthchecks in parallel? (yes/no/quit)"
      read response
      case $response in 
        yes|YES|Yes|y|Y)
          parallel=true
        ;;
        no|NO|No|n|N)
          parallel=false
        ;;
        q|Q|quit|QUIT|Quit)
         exit 0
        ;;
        *)
        echo "Invalid input. Please enter yes or no."
        exit 1
        ;;
      esac
    fi

    # If serial or --latest then iterate through nodes 1x1
    if [[ $parallel == false ]] || [[ $ntype == healthlatest ]]; then

      # Loop through each node and grab the healthcheck
      for n in $nodes
      do
	# Output heading
        echo " "
        echo "----------------------------------------------------------------" 
        echo -e "Healthcheck from node: ${YELLOW}$n${NC} -- Node $currentnumnodes/$numnodes"
        echo "----------------------------------------------------------------" 

	# if fresh or latest
        if [[ $ntype == healthfresh ]]; then
          ssh "$n" "sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py" || { goodhealth=false;echo -e "${RED}ERROR:${NC} Healthcheck for node $n failed. Ensure that node exists, can accept ssh and /opt/oci-hpc/healthchecks/check_gpu_setup.py exists"; }
        else
          ssh "$n" "cat /tmp/latest_healthcheck.log" || { goodhealth=false;echo -e "${RED}ERROR:${NC} Gathering the latest healthcheck for node $n failed."; echo "       Ensure that healthchecks are enabled on the cluster"; }
        fi
        echo " "
        let currentnumnodes++
      done
    else
      # otherwise run healthchecks in parallel
      # output heading
      echo " "
      echo "----------------------------------------------------------------" 
      echo -e "Healthchecks from nodes: $nodes\n" | fold -s -w 65
      echo -e "${YELLOW}Note:${NC} To simplify output only reporting warnings and errors"
      echo "----------------------------------------------------------------" 
      echo " "
      pdsh -S -R ssh -w "$nodes" "sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py -l ERROR -l WARNING" || goodhealth=false
      echo " "

    fi # End serial/parallel healthchecks 

    # If successful then output a good completion status, if errors present then inform user
    if [ $goodhealth == "true" ]; then
      echo -e "${GREEN}Complete:${NC} Healthchecks gathered on $numnodes nodes"
      echo " "
    else
      echo -e "${RED}WARNING:${NC} Healthcheck gathering on $numnodes nodes completed with errors"
      echo " " 
    fi


    # Offer to run ncclscout if number of node is greater then 1, healthchecks are good and ncclscout.py is present in the directory
    if [ $numnodes -gt 1 ] && [ $goodhealth == true ] && [ -f "ncclscout.py" ];then
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

# Main function for --reboot
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

	# loop through list of nodes, output details, send reset signal via ocicli, output success/failure. All output is also sent to a log titled <date>-nodenurse.log
	for n in $nodes
	do

	  # Generate and display info for each node
	  echo "----------------------------------------------------------------" | tee -a $LOG_PATH
          inst=`generate_instance_name $n`
          ocid=`generate_ocid $inst`
	  serial=`generate_serial $n`
          echo -e "Rebooting ${YELLOW}$n${NC}" | tee -a $LOG_PATH
	  echo -e "Instance Name: $inst" | tee -a $LOG_PATH
	  echo -e "Serial Number: $serial" | tee -a $LOG_PATH
	  echo -e "OCID: $ocid" | tee -a $LOG_PATH
	  echo " "

	  # Send hard reboot signal to the node using the generated ocid
          oci compute instance action --instance-id $ocid --action RESET --auth instance_principal >> $LOG_PATH || reboot=false	

	  # If the oci reboot cmd fails then inform user
	  if [ $reboot == false ];
	  then
            echo -e "${RED}Reset failed on $n! Full details in $LOG_PATH${NC}" | tee -a $LOG_PATH 
	  else 
	    echo -e "$(date -u '+%Y%m%d%H%M') - ${GREEN}Success${NC} - Hard reset sent to node ${YELLOW}$n${NC}" | tee -a $LOG_PATH
	  fi
	  echo "----------------------------------------------------------------" | tee -a $LOG_PATH
	  echo " " | tee -a $LOG_PATH

        done # End reboot loop
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

# Main function for tagging hosts unhealthy
if [[ $ntype == tag ]]; then

    # Display node details
    display_nodes
    
    # ask for confirmation before taggin
    echo -e "Are you sure you want to mark these nodes as unhealthy? (yes/no)"
    read response
    echo " " 
    case $response in

      yes|Yes|YES|y|Y)
        echo "Proceeding..."
	echo " "         

	# loop through list of nodes, output details, send reset signal via ocicli, output success/failure. All output is also sent to a log titled <date>-nodenurse.log
	for n in $nodes
	do

	  # Generate and display info for each node
	  echo "----------------------------------------------------------------" | tee -a $LOG_PATH
          inst=`generate_instance_name $n`
          ocid=`generate_ocid $inst`
	  serial=`generate_serial $n`
          echo -e "Tagging ${YELLOW}$n${NC} as unhealthy" | tee -a $LOG_PATH
	  echo -e "Instance Name: $inst" | tee -a $LOG_PATH
	  echo -e "Serial Number: $serial" | tee -a $LOG_PATH
	  echo -e "OCID: $ocid" | tee -a $LOG_PATH
	  echo " "

	  # Send ocid through tagunhealth.py
          /usr/bin/python3 tagunhealthy.py --instance-id $ocid >> $LOG_PATH || goodtag=false	

	  # If the oci reboot cmd fails then inform user
	  if [ $goodtag == false ];
	  then
            echo -e "${RED}Tagging failed on node $n! Full details in $LOG_PATH${NC}" | tee -a $LOG_PATH 
	  else 
	    echo -e "$(date -u '+%Y%m%d%H%M') - ${GREEN}Success${NC} - Node ${YELLOW}$n${NC} marked as unhealthy" | tee -a $LOG_PATH
	  fi
	  echo "----------------------------------------------------------------" | tee -a $LOG_PATH
	  echo " " | tee -a $LOG_PATH

        done # End tagging loop
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
