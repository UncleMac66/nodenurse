#!/bin/bash

HELP_MESSAGE="
Usage: $0 [OPTION] [ARGUMENT]

Description:
  nodenurse.sh takes supplied nodename(s), or a list of nodenames in a hostfile and can run a variety of functions
  on them which can be helpful when troubleshooting an OCI-HPC Slurm based cluster.

Options:
  -h, help             Display this message and exit.
  -c, healthcheck      Run a fresh healthcheck on the node(s).
  -l, latest           Gather the latest healthcheck from the node(s).
  -t, tag              Apply the unhealthy tag to the node(s)
  -st, setuptag        Setup tagging in tenancy
  -r, reboot           Hard reboot the node(s).
  -e, exec             Execute command on the node(s)
  -i, identify         Display full details of the node(s) and exit.
  -n, nccl             Run allreduce nccl test on the node(s).
  -s, ncclscout        Run ncclscout (nccl pair test) on the node(s).
  -u, update           Update the slurm state on the node(s).
  -v, validate         Run nodes through checks to ensure ansible scripts will work.
  captop               Run a report on capacity topology if tenancy is enabled for it

Arguments:
  HOST(S)                An input hostfile, or space separated list of hostnames (e.g. gpu-1 gpu-2).

  --all,-a               Use all hosts that are listed in slurm.

  --idle                 Use hosts that are in a 'idle' state in slurm.

  --drain                Use hosts that are in a 'drain' state in slurm.

  --down                 Use hosts that are in a 'down' state in slurm.

  --alldown              Use hosts that are in a 'down' or 'drain' state in slurm.

  --maint                Use hosts that are in a 'maint' state in slurm.

  --partition,-p <name>  Use all nodes in a specified slurm partition name (i.e. compute).


Examples:
  $0 -c <path/to/hostfile>    runs a fresh healthcheck on the node(s) in the provided hostlist.
  $0 -r gpu-1                 sends a hard reboot signal to node 'gpu-1'.
  $0 -v --all                 validates all nodes
  $0 latest --alldown         grabs the latest healthchecks from nodes marked as drain or down in slurm.
  $0 identify gpu-1 gpu-2     display details about 'gpu-1' and 'gpu-2' then quit.

Notes:
  - nodenurse.sh gets compartment OCID from /opt/oci-hpc/conf/queues.conf.
    If you use queues across compartments please double check this value and consider 
    hard-coding it to your use case.

  - In order for tagging hosts as unhealthy to work properly, your tenancy must be properly
    whitelisted for unhealthy instance tagging.

  - nodenurse.sh deduplicates your provided hostlist.
"

HELP_BRIEF="usage: $0 [-c, healthcheck] [-l, latest] [-r, reboot]
                      [-i, identify] [-t, tag] [-n, nccl] [ -v, validate ]
		      [-s, ncclscout] [-u, update] [-h, help] [-e, exec]
                      [Arguments {HOST(S),HOSTFILE,--all,--idle,--drain,--down,
	                          --alldown,--partition <name>}]"

# Check if an argument is passed
if [ -z "$1" ]; then
    echo "$HELP_BRIEF"
    exit 1
fi

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

# Create nccl_tests folder if it doesn't exist
NCCL_FOLDER="nccl_tests"
if [ ! -d "$NCCL_FOLDER" ]; then
  mkdir -p "$NCCL_FOLDER"
fi

# Initialize global variables
compartmentid=$(cat /opt/oci-hpc/conf/queues.conf | grep targetCompartment: | sort -u | awk '{print $2}')
reboot=true
goodtag=true
allocstate=false
parallel=false
goodhealth=true
goodssh=true
goodinst=true
goodslurm=true
goodstate=true

# warn function
warn(){
    echo -e "${YELLOW}WARNING:${NC} $1\n"
}

# error function
error(){

    if [ -n "$1" ]; then
      echo -e "${RED}ERROR:${NC} $1\n"
    fi
    echo -e "Exiting...\n"
    exit 1
}

# Check first argument to grab function or exit if no valid option is provided
if [[ $1 == "-c" ]] || [[ $1 == "healthcheck" ]]; then
    ntype=healthfresh
    echo -e "\nFresh Healthcheck Mode...\n"

elif [[ $1 == "-l" ]] || [[ $1 == "latest" ]]; then
    ntype=healthlatest
    echo -e "\nLatest Healthcheck Mode...\n"

elif [[ $1 == "-r" ]] || [[ $1 == "reboot" ]]; then
    ntype=rebootall
    echo -e "\nReboot Mode...\n"

elif [[ $1 == "-i" ]] || [[ $1 == "identify" ]]; then
    ntype=idnodes
    echo -e "\nIdentify Mode...\n"

elif [[ $1 == "-t" ]] || [[ $1 == "tag" ]]; then
    ntype=tag
    echo -e "\nTagging Mode...\n"

elif [[ $1 == "-n" ]] || [[ $1 == "nccl" ]]; then
    ntype=nccl
    echo -e "\nFull NCCL Mode...\n"

elif [[ $1 == "-s" ]] || [[ $1 == "ncclscout" ]]; then
    ntype=ncclscout
    echo -e "\nncclscout Mode...\n"

elif [[ $1 == "-u" ]] || [[ $1 == "update" ]]; then
    ntype=update
    echo -e "\nUpdate Mode...\n"

elif [[ $1 == "-e" ]] || [[ $1 == "exec" ]]; then
    ntype=exec
    echo -e "\nRemote exec Mode...\n"

elif [[ $1 == "-v" ]] || [[ $1 == "validate" ]]; then
    ntype=validate
    echo -e "\nValidate Mode...\n"

elif [[ $1 == "setuptag" ]]; then
    ntype=setuptag
    echo -e "\nSetup Tagging Mode...\n"

elif [[ $1 == "captop" ]]; then
    ntype=captop
    echo -e "\nCapacity Topology Mode...\n"

elif [[ $1 == "-h" ]] || [[ $1 == "--help" ]] || [[ $1 == "help" ]]; then
    echo "$HELP_MESSAGE"
    exit 0

else
    echo "$HELP_BRIEF"
    echo -e "\nUnknown option '$1' Please try again\n"
    exit 1

fi # End option check


# Host/hostfile Input
# If a second argument is passed, assume its a nodename or a hostfile. If no second argument is passed check if a slurm state flag is passed 
shift
while [[ $# -gt 0 ]]; do

    if [ -f "$1" ]; then

      # arg is a hostfile
      echo -e "\nReading from provided hostfile...\n"
      for i in $(cat "$1")
      do
        nodes+="$i "
      done
      break
    elif [ -z "$1" ]; then

      # no argument provided so ask for a slurm status
      echo -e "\nNo hosts provided.\n\nPlease provide hosts manually, or specify a slurm status (i.e. --idle, --down, --drain, --all)\n"
      break
    fi

    case "$1" in 

      -p|--partition)
	if [[ $# -lt 2 ]] || [ "${2:0:1}" == "-" ]; then
	  error "-p/--partition requires a specified partition. (i.e. '-p compute')"
        fi
        echo -e "Filtering hosts from the $2 partition...\n"
        gatherpartition="-p $2"
        shift 2
        ;;

      -a|--all)
        if [ -z "$gatherstate" ]; then
	  echo -e "Filtering all hosts from slurm...\n"
	  gatherstate="-t all"
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
        shift
        ;;

      --down)
        if [ -z "$gatherstate" ]; then
          echo -e "Filtering hosts from slurm marked as 'down'...\n"
	  gatherstate="-t down"
          shift
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
        ;;

      --drain)
        if [ -z "$gatherstate" ]; then
          echo -e "Filtering hosts from slurm marked as 'drain'...\n"
	  gatherstate="-t drain"
	  shift
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
	;;

      -dd|--alldown)
        if [ -z "$gatherstate" ]; then
          echo -e "Filtering hosts from slurm marked as 'down' and 'drain'...\n"
	  gatherstate="-t drain,down"
	  shift
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
	;;

      --idle)
        if [ -z "$gatherstate" ]; then
          echo -e "Filtering hosts from slurm marked as 'idle'...\n"
	  gatherstate="idle"
	  shift
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
	;;

      --maint)
        if [ -z "$gatherstate" ]; then
          echo -e "Filtering hosts from slurm marked as 'maint'...\n"
	  gatherstate="-t maint"
	  shift
        else
	  echo -e "--${gatherstate:3} already given, ignoring $1...\n"
	  break
	fi
	;;

      *)
        if [ "${2:0:1}" == "-" ]; then
          # arg is a mistyped flag so quit
          echo -e "Unknown argument '$2'"
          echo -e "Please provide hosts manually, or specify a slurm status (i.e. --idle, --down, --drain, --all)\n"
          exit 1
        else
          # arg is/are manually entered hostname(s)
          for arg in "${@:1}"; do
            nodes+="$arg "
          done
          echo -e "Hostname(s) provided manually...\n"
	  break
	fi
	shift
        ;;

  esac
done

# Process nodelist
if [[ -n $gatherpartition ]] || [[ -n $gatherstate ]]; then
    if [[ $gatherstate = "idle" ]]; then
      nodes=$(sinfo $gatherpartition -N -h | grep idle | awk '{print $1}')
    else
      nodes=$(sinfo $gatherpartition $gatherstate -h -o %n)
    fi
fi

# deduplicate nodelist
nodes=$(echo $nodes | tr " " "\n" | sort -u | tr "\n" " " )

# get number of nodes
numnodes=$(echo $nodes | wc -w) 

# Get reservation ID if exists 
for i in $nodes; do
    activeres+="$(sinfo -h -o "%n %i" | grep ubuntu | grep "$i " | awk '{print $2}') "
done

# depuplicate
activeres=$(echo $activeres | tr " " "\n" | sort -u | tr "\n" " " )

if [[ $(echo $activeres | wc -w) -gt 1 ]] && [[ $ntype == nccl ]]; then
    error "Multiple reservations exist on these nodes, full nccl tests will fail"
elif [[ $(echo $activeres | wc -w) -eq 1 ]]; then
    reservation="--reservation="$activeres""
else
    reservation=""
fi

confirm(){

    if [ -n "$1" ]; then
      prompt="$1 (yes/no/quit)"
    else
      prompt="Continue? (yes/no/quit)"
    fi

    while true; do 
      echo -e "$prompt"
      read response
      case $response in 
        y|Y|yes|Yes|YES)
          return 0
	  break
	  ;;
        n|N|no|No|NO) 
	  return 1
	  break
	  ;;
        q|Q|quit|Quit|QUIT)
	  exit 0
	  ;;
        *) 
	  warn "Invalid input. Please enter yes or no."
	  ;;
      esac
    done
}


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
    outputocid=`ssh $1 -o "ConnectTimeout=5" "curl -sH \"Authorization: Bearer Oracle\" -L http://169.254.169.254/opc/v2/instance/ | jq -r .id"`
    if [[ -z $outputocid ]]; then 
	outputocid=$(oci compute instance list --compartment-id $compartmentid --display-name `generate_instance_name $1` --auth instance_principal | jq -r  .data[0].id)
    fi
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

finddiff(){

    list1=$1
    list2=$2

    # Convert the lists to arrays
    arr1=($list1)
    arr2=($list2)

    # Find the difference between the arrays
    diff_arr=()
    for node in "${arr1[@]}"; do
      if ! [[ " ${arr2[*]} " =~ " $node " ]]; then
        diff_arr+=("$node")
      fi
    done
    for node in "${arr2[@]}"; do
      if ! [[ " ${arr1[*]} " =~ " $node " ]]; then
        diff_arr+=("$node")
      fi
    done

    # Join the difference array into a space-separated string
    diff_str=$(IFS=' '; echo "${diff_arr[*]}")

    # Print the difference
    echo "$diff_str"
}



# Function takes in a hostname (e.g. gpu-123) and returns it's shape
generate_shape() {
  outputshape=`ssh $1 -o "ConnectTimeout=5" "curl -sH \"Authorization: Bearer Oracle\" -L http://169.254.169.254/opc/v2/instance/ | jq -r .shape"`
  echo $outputshape
}

# Function takes in a hostname (e.g. gpu-123) and returns it's serial number
generate_serial() {
    outputserial=`ssh -o "ConnectTimeout=5" $1 "sudo dmidecode -s system-serial-number" || echo -e "Error: SSH"`
    echo $outputserial
}

# Function to send nodes through ncclscout
nccl_scout() {

    if [ $numnodes = 1 ]; then
      error "Must have at least 2 nodes!"
    fi

    for i in $nodes
    do
      echo $i >> $date-hostfile.tmp
    done

    python3 bin/ncclscout.py $date-hostfile.tmp
    cleanup
    echo ""

}

# Function to check shape of nodes and exit if unsupported
check_shape() {

    echo -e "Getting shapes and testing ssh to nodes... \n"

    shapes=$(pdsh -N -S -R ssh -t 5 -w "$nodes" "curl -sH \"Authorization: Bearer Oracle\" -L http://169.254.169.254/opc/v2/instance/ | jq -r .shape")

    if [ $? -gt 0 ]; then
      echo -e "${RED}ERROR:${NC} There are node(s) that are inaccessable via ssh.\n"
      exit 1
    fi

    # Deduplicate list of shapes
    shapes=`echo $shapes | tr " " "\n" | sort -u | tr "\n" " "`

    if [ $(echo $shapes | wc -w) -gt 1 ]; then
	echo -e "${RED}ERROR:${NC} There are multiple types of shapes in this hostlist\n"
	exit 1
    fi

    shapes=$(echo $shapes | awk -F '.' '{print $3}')

    # Check node shape and set the right sbatch script
    case "$shapes" in
    B4|A100|A100-v2) script="/opt/oci-hpc/samples/gpu/nccl_run_allreduce.sbatch";;
    H100|H200)
      if [ -f "/opt/oci-hpc/samples/gpu/nccl_run_allreduce_H100_200.sbatch" ]; then
        script="/opt/oci-hpc/samples/gpu/nccl_run_allreduce_H100_200.sbatch"
      else
        script="/opt/oci-hpc/samples/gpu/nccl_run_allreduce_H100.sbatch"
      fi
    ;;
    *) echo -e "${RED}ERROR:${NC} Unsupported shape found. nccl testing only supports A100, H100 and H200"; exit 1 ;;
    esac

}

cleanup(){

    find . -maxdepth 1 -name '*.tmp' -print0 | while IFS= read -r -d '' tmpfile
    do
      rm "$tmpfile"
    done

    find . -maxdepth 1 -name '*.log' -print0 | while IFS= read -r -d '' logfile
    do
      mv "$logfile" "logs"
    done

    find "." -maxdepth 1 -type d -regex '^.*[0-9].*' -print0 | while IFS= read -r -d '' dir; do
      mv "$dir" "nccl_tests/"
    done

}

execute(){

    local currentnumnodes=1
    local execparallel=false
    local cmd=""

    # Check if the -p flag is present
    if [[ "$1" == "-p" ]]; then
        execparallel=true
        shift
    fi

    # Get the command to run
    cmd="$*"

    if [[ $execparallel == false ]]; then

      for n in $nodes
      do
        echo -e "\n----------------------------------------------------------------" 
        echo -e "Output from node: ${YELLOW}$n${NC} -- Node $currentnumnodes/$numnodes"
        echo -e "----------------------------------------------------------------\n" 
        ssh -o "ConnectTimeout=5" "$n" "$cmd"
	returnval+=$?
	echo ""
        let currentnumnodes++
      done
    else
      echo -e "\n----------------------------------------------------------------" 
      echo -e "Output from nodes: ${YELLOW}$nodes${NC}" | fold -s -w 65
      echo -e "----------------------------------------------------------------\n" 
      pdsh -S -R ssh -t 5 -w "$nodes" "$cmd"
      returnval=$?
      echo ""
    fi 

    return $returnval

}


# Function displays the list of hosts along with relevant information, checking for nodes that can't be ssh'd or are in an allocated state in slurm
display_nodes(){

    cleanup
    goodstate=true

    echo "----------------------------------------------------------------"
    echo "---------------------- `date -u +'%F %T'` ---------------------"
    echo -e "----------------------------------------------------------------\n"
    if [[ $1 == "full" ]]; then
      printf "%-25s %-25s %-15s %-15s %-10s\n" "Hostname" "Instance Name" "Host Serial" "Shape" "Slurm State"
      echo " " 
    else
      printf "%-25s %-25s %-10s\n" "Hostname" "Instance Name" "Slurm State"
      echo " " 
    fi

    if [ `echo $nodes | wc -w` -eq 0 ];then
      error "No hosts to list."
    fi

    # Loop through each node and get its instance name and details
    for n in $nodes
    do

      # Gather details
      inst=`generate_instance_name $n`
      state=`generate_slurm_state $n`

      # Node error checking
      case $state in
	mix|alloc) allocstate=true;;
        drain|down|drng) goodstate=false;;
	"Not Found") goodslurm=false;;
      esac

      if [[ $inst == "Not Found" ]]; then
	goodinst=false
      fi

      # output node data
      if [[ $1 == "full" ]]; then

        serial=`generate_serial $n`
	ocid=`generate_ocid $n`
	shape=`generate_shape $n`

        if [[ $serial == "Error: SSH" ]]; then
          goodssh=false
        fi

	printf "%-25s %-25s %-15s %-15s %-10s\n" "$n" "$inst" "$serial" "$shape" "$state"
        echo -e "  \u21B3 $ocid"
        echo " "

      else

        printf "%-25s %-25s %-10s" "$n" "$inst" "$state"
        echo " "

      fi

    done

    # Display total num of nodes
    echo -e "\nTotal: $numnodes Distinct host(s)\n"

    # If down/drain nodes then display reasons
    if [ -n "$(sinfo -R -h)" ] && [ $goodstate == "false" ];then
      echo -e "More detail on down/drain nodes:\n"
      sinfo -R -o "%25n %6t %E" | head -1
      for i in $nodes
      do
	sinfo -R -o "%25n %6t %E" | grep --color=always "$i "
      done
      echo ""
    fi

    # if any nodes are in alloc state then warn user
    if [[ $allocstate == true ]]; then
      warn "There are hosts in an allocated state.\n\nProceed with caution as some actions, like rebooting, can cause significant customer disruption"
    fi

    # If instance name is not in /etc/hosts
    if [[ $goodinst == false ]] || [[ $goodslurm == false ]] || [[ $goodssh == false ]]; then
      warn "These are hosts that either can't be found in /etc/hosts or slurm.\nThe host(s) may not exist, were mistyped, or were not correctly added to the cluster"
    fi

}

# Main Function for --identify
if [ $ntype == idnodes ]; then

    # Just display the node information and exit
    display_nodes full
    exit 0

fi

# Main Function for --healthcheck and --latest
if [[ $ntype == healthfresh ]] || [[ $ntype == healthlatest ]]; then

    # Initialize the node count and display node details
    display_nodes

    # Prompt user for parallelism if running fresh healthcheck and number of nodes is greater than 2 otherwise just run sequentially
    if [[ $numnodes -gt 2 ]] && [[ $ntype == healthfresh ]]; then
      confirm "Do you want to run healthchecks in parallel?"
      if [ $? -eq 0 ]; then
          parallel=true
      else
          parallel=false
      fi
    else
      confirm || exit 0
    fi

    # If serial or --latest then iterate through nodes 1x1
    if [[ $parallel == false ]] || [[ $ntype == healthlatest ]]; then

      # if fresh or latest
      if [[ $ntype == healthfresh ]]; then
        execute sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py || { goodhealth=false;echo -e "${RED}ERROR:${NC} Healthcheck for node $n failed. Ensure that node exists, can accept ssh and /opt/oci-hpc/healthchecks/check_gpu_setup.py exists"; }
      else
        execute cat /tmp/latest_healthcheck.log || { goodhealth=false;echo -e "${RED}ERROR:${NC} Gathering the latest healthcheck for node $n failed."; echo "       Ensure that healthchecks are enabled on the cluster"; }
      fi
      echo " "
    else
      # otherwise run healthchecks in parallel
      echo -e "\nNote: To keep output brief, only reporting on errors and warnings"
      execute -p sudo python3 /opt/oci-hpc/healthchecks/check_gpu_setup.py -l ERROR -l WARNING || goodhealth=false
    fi # End serial/parallel healthchecks 

    # If successful then output a good completion status, if errors present then inform user
    if [ $goodhealth == "true" ]; then
      echo -e "${GREEN}Complete:${NC} Healthchecks gathered on $numnodes nodes\n"
    else
      warn "Healthcheck gathering on $numnodes nodes completed with errors"
    fi


    # Offer to run ncclscout if number of node is greater then 1, healthchecks are good and ncclscout.py is present in the directory
    if [ $numnodes -gt 1 ] && [ $goodhealth == true ] && [ -f "bin/ncclscout.py" ];then
      confirm "Would you like to run ncclscout on these $numnodes nodes?" || exit 0
      check_shape
      nccl_scout
    fi

fi

# Main function for --reboot
if [ $ntype == rebootall ]; then

    display_nodes

    # ask for confirmation before reboot
    confirm "Are you sure you want to force reboot the node(s)?" || exit 0

	# loop through list of nodes, output details, send reset signal via ocicli, output success/failure. All output is also sent to a log titled <date>-nodenurse.log
	for n in $nodes
	do

	  # Generate and display info for each node
	  echo -e "\n----------------------------------------------------------------" | tee -a $LOG_PATH
          inst=`generate_instance_name $n`
          ocid=`generate_ocid $n`
	  serial=`generate_serial $n`
          echo -e "Rebooting ${YELLOW}$n${NC}" | tee -a $LOG_PATH
	  echo -e "Instance Name: $inst" | tee -a $LOG_PATH
	  echo -e "Serial Number: $serial" | tee -a $LOG_PATH
	  echo -e "OCID: $ocid\n" | tee -a $LOG_PATH

	  # Send hard reboot signal to the node using the generated ocid
          oci compute instance action --instance-id $ocid --action RESET --auth instance_principal >> $LOG_PATH || reboot=false	

	  # If the oci reboot cmd fails then inform user
	  if [ $reboot == false ];
	  then
            echo -e "${RED}Reset failed on $n! Full details in $LOG_PATH${NC}" | tee -a $LOG_PATH 
	  else 
	    echo -e "$(date -u '+%Y%m%d%H%M') - ${GREEN}Success${NC} - Hard reset sent to node ${YELLOW}$n${NC}" | tee -a $LOG_PATH
	  fi
	  echo -e "----------------------------------------------------------------\n" | tee -a $LOG_PATH

        done # End reboot loop
fi

if [[ $ntype == setuptag ]]; then

    # Check if tag namespace is properly set up
    # if not then set them up properly
    echo -e "Checking if tags are properly set up..."
    /usr/bin/python3 bin/tagunhealthy.py --check
    if [ $? -gt 0 ]; then
      confirm "Want nodenurse to set up tagging?" || exit 0
      echo -e "Setting up tags...\n"
      /usr/bin/python3 bin/tagunhealthy.py --setup
      if [ $? -gt 0 ];then 
        error "Error setting up tagging!"
      fi
    fi
    echo ""
    
fi
# Main function for tagging hosts unhealthy
if [[ $ntype == tag ]]; then

    # Display node details
    display_nodes
    
    # ask for confirmation before tagging
    confirm "Are you sure you want to mark the node(s) as unhealthy?" || exit 0

    # loop through list of nodes, output details, send reset signal via ocicli, output success/failure. All output is also sent to a log titled <date>-nodenurse.log
    for n in $nodes
    do
      # Generate and display info for each node
      echo -e "\n----------------------------------------------------------------" | tee -a $LOG_PATH
      inst=`generate_instance_name $n`
      ocid=`generate_ocid $n`
      serial=`generate_serial $n`
      echo -e "Tagging ${YELLOW}$n${NC} as unhealthy" | tee -a $LOG_PATH
      echo -e "Instance Name: $inst" | tee -a $LOG_PATH
      echo -e "Serial Number: $serial" | tee -a $LOG_PATH
      echo -e "OCID: $ocid\n" | tee -a $LOG_PATH

      # Send ocid through tagunhealth.py
      /usr/bin/python3 bin/tagunhealthy.py --instance-id $ocid >> $LOG_PATH || goodtag=false	

      # If the oci reboot cmd fails then inform user
      if [ $goodtag == false ]; then
        echo -e "${RED}Tagging failed on node $n! Full details in $LOG_PATH${NC}" | tee -a $LOG_PATH 
      else 
        echo -e "$(date -u '+%Y%m%d%H%M') - ${GREEN}Success${NC} - Node ${YELLOW}$n${NC} marked as unhealthy" | tee -a $LOG_PATH
      fi
      echo -e "----------------------------------------------------------------\n" | tee -a $LOG_PATH

    done # End tagging loop

fi

# Main function for full nccl test on nodes
if [[ $ntype == nccl ]]; then

    display_nodes 

    if [[ $allocstate == true ]] || [[ $goodstate == false ]]; then
     error "Some nodes are in an allocated or down state. Can't run NCCL test."
    fi

    check_shape

    echo -e "How many times to run the NCCL test?"
    read numtimes
    if [[ $numtimes =~ ^[1-9][0-9]*$ ]]; then

      # mv nodeorderingbyrack.py if needed
      if [ ! -f "/home/ubuntu/node_ordering_by_rack.py" ]; then
        sudo cp /opt/oci-hpc/bin/node_ordering_by_rack.py /home/ubuntu/
      fi

      if [ ! -d "nccl_tests/" ]; then
	mkdir nccl_tests/
      fi

      echo ""
      for i in $(seq 1 $numtimes)
      do
	sbatch -N $numnodes -w "$nodes" \
	  --job-name=nodenurse_nccl \
	  --output=nccl_tests/nccl_job-%j.out \
	  --error=nccl_tests/nccl_job-%j.err \
	  $reservation\
	  $script \
	  | tee -a jobid.tmp
      done

      if [ $? -gt 0 ]; then
        error "sbatch encountered a problem.."
      fi
	
      jobids=`cat jobid.tmp| awk '{print $4}'`
      cleanup
      echo ""
    
      echo -e "Waiting for jobs to finish.\n"
      goodjob=true
      numtest=1
      timetowait=0
      output=true

      for j in $jobids
      do
        jobstate=`sacct -j "$j" -n -o "JobID,State" | grep "$j " | awk '{print $2}'`

	while [[ $jobstate != "COMPLETED" ]]
	do
          jobstate=`sacct -j "$j" -n -o "JobID,State" | grep "$j " | awk '{print $2}'`
	  sleep .25
	  echo -ne "\r |                          "
	  sleep .25
	  echo -ne "\r /                          "
	  sleep .25
	  echo -ne "\r -                          "
	  sleep .25
	  echo -ne "\r \\                          "
	  let timetowait++
	  if [[ $jobstate == "FAILED" ]]; then
	    goodjob=false
	    break
	  fi
	  if [[ $timetowait -gt 90 ]]; then
	    warn "Timed out waiting for nccl Job $j."
	    output=false
	    break
	  fi
        done

        echo -e "\n----------------------------------------------------------------" 
	echo -e "NCCL Test $numtest/$numtimes - ${YELLOW}JobID: $j${NC} - Time taken ~ $timetowait Seconds"
        echo -e "----------------------------------------------------------------\n" 
	if [ $goodjob = true ] && [ $output = true ]; then
	  tail -15 nccl_tests/nccl_job-$j.out
          echo -e "Full output stored at: nccl_tests/nccl_job-$j.out\n"
	
        elif [ $goodjob = false ] && [ $output = true ]; then
          echo -e "${RED}ERROR:${NC} Job $j encountered a problem...\n"
          tail -15 nccl_tests/nccl_job-$j.err
          echo -e "\nFull error output stored at: nccl_tests/nccl_job-$j.err\n"
	  goodjob=true
        else
	  warn "No output to show. Check on this job manually with squeue."
	fi
	let numtest++
	timetowait=0
      done

      # clean up nccl script output
      cleanup

    else
      error "Invalid input. Please enter a positive integer."
    fi

fi

# Main function for sending nodes to ncclscout
if [[ $ntype == ncclscout ]]; then

    display_nodes
    check_shape
    nccl_scout

fi

# Main function for updating hosts
if [[ $ntype == update ]]; then

    display_nodes

    echo -ne "Select option to apply:
1. Set node(s) to 'resume'
2. Set node(s) to 'drain'
3. Set node(s) to 'down'
4. Create a 2 hour maintenance reservation on node(s)
5. Clear all reservations
6. Quit

${YELLOW}Reminder${NC}: Putting nodes that are allocated into a down state will kill those jobs immediately.
          Drain is nicer and will wait for the running job to finish. 

Selection: "
    read response
    case $response in
      1) 
         for i in $nodes
         do
           s=`generate_slurm_state $i`
	   case "$s" in
	     idle|mix|alloc|maint|drng) ;;
	     *) sudo scontrol update nodename="$i" state=resume;;
           esac
         done
      ;;

      2)
         echo -ne "Enter a reason: "
         read reason
         for i in $nodes
         do
           s=`generate_slurm_state $i`
	   case "$s" in
	     drain|down|drng) ;;
	     *) sudo scontrol update nodename="$nodes" state=drain reason="$reason";;
           esac
         done
      ;;

      3) 
         echo -ne "Enter a reason:"
         read reason
         for i in $nodes
	 do
           s=`generate_slurm_state $i`
	   case "$s" in
	     down|drain) ;; 
	     *) sudo scontrol update nodename="$nodes" state=down reason="$reason";;
           esac
         done
         ;;

      4) 
         sudo scontrol create reservation starttime=`date -u +'%FT%T'` flags=maint,ignore_jobs user=$USER duration=120 nodes="$nodes" && sleep 1 
         if [ $? -ne 0 ]; then
           error "Couldn't create slurm reservation."
         fi
	 
         for i in $nodes
         do
           s=`generate_slurm_state $i`
           if [ $s == "drain" ] || [ $s == "down" ]; then
             sudo scontrol update nodename="$i" state=resume
           fi
         done

         resname=`sinfo --reservation | tail -1 | grep "$USER" | awk '{print $1}'`
         if [ -z $resname ];then resname="<RESV_NAME>";fi

         echo -e "\n  Reservation created and nodes set to 'maint' state.

  To schedule jobs on these nodes use the following commands

  ### run cmd samples ###

  sbatch -N <# nodes> --reservation=$resname example.sbatch

  srun -w <specific nodename> --reservation=$resname --gpus=8 <cmd>

  ### To take out of 'maint' state ###

  sudo scontrol delete reservation=$resname

  ### For more details ###

  scontrol show reservation

Current Reservations:"
        sinfo --reservation
        echo ""
        ;;

      5)
	for i in $(sinfo -h -o %h)
        do
          sudo scontrol delete reservation="$i"
	done
	;;
      6) exit 0 ;;

      *) echo -e "Invalid Input\n"; exit 1 ;;

    esac  
   
    echo ""
    sleep 2
    display_nodes
    exit 0

fi

if [[ $ntype == exec ]]; then

    display_nodes

    parallel=true

    while true; do
      # Ask for cmd to run
      echo -e "Please enter the command you'd like to run on these node(s)\n[ q: quit, s: sequential mode, p: parallel mode (default) ]\n"
      if [[ $parallel == false ]]; then
        echo -e "${GREEN}Sequential Mode${NC}"
      else
        echo -e "${GREEN}Parallel Mode${NC}"
      fi
      echo -ne "$ "
      read cmd
      echo ""
      case "$cmd" in
	q) exit 0;;
	s) parallel=false;;
	p) parallel=true;;
	*)
          # Run commands
          if [[ $parallel == false ]]; then
            execute $cmd
          else
            execute -p $cmd
          fi
	;;
      esac
    done

fi

if [[ $ntype == validate ]]; then

    badsminodes=""
    numtimes=0
    display_nodes

    warn "Validate mode is not a robust healthcheck. 
         It should only be used to diagnose why ansible playbooks may be hanging/failing."

    confirm || exit 0

    echo -e "\nChecking for nvidia-smi errors...\n"
    smiresults=`parallel-ssh -i -l ubuntu -H "$nodes" -t 15 "hostname;nvidia-smi | grep NVIDIA-SMI"`

    if echo -e "$smiresults" | grep --color=always "FAILURE"; then
      echo -e "\nThe following nodes have nvidia-smi issues:\n"
      badsminodes=$(echo -e "$smiresults" |grep "FAILURE" | awk '{print $4}')
      echo -e "${RED}$badsminodes${NC}"
      echo "" 
    fi

    echo -e "Checking gather facts on full list of nodes...\n"

    for i in $nodes
    do
      echo $i >> $date-hostfile.tmp
    done

    timeout 20s ansible-playbook -T 3 -i $date-hostfile.tmp bin/gather_facts.yml | tee logs/$date-validate.log
    oknodes=`cat logs/$date-validate.log | grep "ok:" | awk -F'[][]' '{print $2}'`

    if ! [ $(echo "$oknodes" | wc -w) = $numnodes ]; then
      
      if [ -n "$badsminodes" ]; then
        retestnodes=`finddiff "$nodes" "$oknodes"`
	retestnodes=`finddiff "$badsminodes" "$retestnodes"`
	echo ""
        warn "Ansible gather facts is failing, trying to find the offending node(s)..."
        warn "Trying again but removing the following node(s) with nvidia-smi issues"
        echo -e "${RED}$badsminodes${NC}"
        rm $date-hostfile.tmp
        for i in $retestnodes
        do
          echo $i >> $date-hostfile.tmp
        done
	echo ""
        timeout 20s ansible-playbook -T 3 -i $date-hostfile.tmp bin/gather_facts.yml | tee -a logs/$date-validate.log 
        oknodes=`cat logs/$date-validate.log | grep "ok:" | awk -F'[][]' '{print $2}'`
        retestnodes=`finddiff "$nodes" "$oknodes"`
      else
        echo ""
        warn "Ansible gather facts is failing, trying to find the offending node(s)..."
        retestnodes=`finddiff "$nodes" "$oknodes"`
        echo -e "Nodes that are ok:"
        echo -e "${GREEN}$oknodes${NC}"
        echo -e "\nNodes that will be retested:"
        echo -e "${YELLOW}`echo $retestnodes | tr " " "\n"`${NC}"
        echo ""
        rm $date-hostfile.tmp
        for i in $retestnodes
        do
          echo $i >> $date-hostfile.tmp
        done
        timeout 20s ansible-playbook -T 3 -i $date-hostfile.tmp bin/gather_facts.yml | tee -a logs/$date-validate.log 
        oknodes=`cat logs/$date-validate.log | grep "ok:" | awk -F'[][]' '{print $2}'`
        retestnodes=`finddiff "$nodes" "$oknodes"`
      fi

#      warn "Attempting fix..."
#      for i in $retestnodes
#      do
#	badnvme=`ssh $i lspci | grep NVMe | grep "rev ff"`
#	if "$badnvme"; then
#          deviceids=`ssh $i lspci | grep NVMe | grep "rev ff" | awk -F ':' '{print $1}'`
#	  for i in $deviceids
#	  do
#            ssh $i "sudo -c \"echo 1 > /sys/bus/pci/devices/0000\:$i\:00.0/remove\""
#         done
#	fi
#      done

      echo -e "Nodes that are ok (`echo $oknodes | wc -w`):"
      echo -e "${GREEN}`echo $oknodes | tr "\n" " " | fold -s -w 65`${NC}"
      echo -e "\nNodes that have potential issues (`echo $retestnodes | wc -w`):"
      echo -e "${RED}`echo $retestnodes | tr " " "\n"`${NC}"

    else
      echo -e "${GREEN}Success:${NC} Nodes are ansible validated and should work fine."
    fi

    cleanup
    exit 0

fi

if [[ $ntype == captop ]]; then
    captopid=$(oci compute capacity-topology list --compartment-id "$compartmentid" --auth instance_principal | jq -r .data.items[].id)
    if [[ -z $captopid ]]; then
      error "Cannot find the capacity topology id, are you sure one is active in this compartment?"
    fi
    bin/runcaptopreport.py --capacity-id $captopid
    cleanup
    exit 0
fi
