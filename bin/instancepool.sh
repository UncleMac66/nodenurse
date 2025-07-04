#!/bin/bash

ACTION=$1
QTY=$2

# ------------------ CONFIGURATION ------------------
PARTITION="cpu" # Replace with actual slurm partition
POOL_OCID="ocid1.instancepool.oc1.iad.aaaaaaaa"  # Replace with actual instance pool OCID
COMPARTMENT_OCID="ocid1.compartment.oc1..aaaaaaaa" # Replace with actual compartment OCID
# ---------------------------------------------------

if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
  echo -e "Usage: $0 start <# of nodes>|stop <# of nodes>\n\nExample: ./instancepool.sh start 20  ->  will start 20 nodes in specified instance pool\n         ./instancepool.sh stop -> will stop all nodes in specified instance pool"
  exit 1
fi
if  [[ ! "$QTY" =~ ^[0-9]+$ ]] && [[ -n "$QTY" ]]; then
  echo "Please enter a valid postive integer"
  exit 1
fi

# Handle stop operation
if [[ "$ACTION" == "stop" ]] && [[ -z "$QTY" ]]; then
  echo "[INFO] Performing '$ACTION' operation on Slurm $PARTITION partition nodes..."
  echo "[INFO] Stopping $PARTITION instance pool..."
  oci compute-management instance-pool stop --instance-pool-id "$POOL_OCID" --wait-for-state STOPPED --wait-interval-seconds 5 --auth instance_principal

# Mark stopped nodes as drain in slurm
  echo "[INFO] Marking nodes in Slurm as DRAIN..."
  sinfo -p $PARTITION -ho %n | xargs -I {} sudo scontrol update NodeName="{}" State=DOWN Reason="Manually Paused to stop billing"
  echo "[INFO] Stop operation complete. Nodes are now DOWN."
  exit 0
fi

# Handle stop operation w/ qty specified
if [[ "$ACTION" == "stop" ]] && [[ -n "$QTY" ]]; then 
  echo "[INFO] Performing '$ACTION' operation on $QTY Slurm $PARTITION partition nodes..."
  hosts=$(sinfo -h -o %n -t idle -p $PARTITION | head -n $QTY)
  if [[ -z $hosts ]]; then
    echo  "[ERROR] There are no hosts in an idle state to stop..."
    exit 1
  fi
  if [[ `echo $hosts | wc -w` -lt "$QTY" ]]; then
    echo "[WARNING] Can only stop `echo $hosts | wc -w` hosts instead of the requested $QTY..."
  fi
  for i in $hosts
  do
    ociname=`cat /etc/hosts | grep "$i " | awk '{print $4}'`
    ocid+=" $(oci compute instance list --compartment-id $COMPARTMENT_OCID --display-name $ociname --auth instance_principal | jq -r .data[0].id)"
  done
  echo "[INFO] Marking nodes as DOWN..."
  echo $hosts | tr " " "\n" | xargs -I {} sudo scontrol update NodeName="{}" State=DOWN Reason="Manually Paused to stop billing"
  echo "[INFO] Stopping nodes..."
  echo $ocid | tr " " "\n" | xargs -P 0 -I {} oci compute instance action --action STOP --instance-id {} --wait-for-state STOPPED --wait-interval-seconds 5 --auth instance_principal
  echo "[INFO] Stop operation complete. `echo $hosts | wc -w` nodes are now DOWN..."
  exit 0
fi

# Handle start operation
if [[ "$ACTION" == "start" ]] && [[ -z "$QTY" ]]; then
  echo "[INFO] Performing '$ACTION' operation on Slurm $PARTITION partition nodes..."
  echo "[INFO] Starting $PARTITION instance pool..."
  oci compute-management instance-pool start --instance-pool-id "$POOL_OCID" --wait-for-state RUNNING --wait-interval-seconds 5 --auth instance_principal

# Mark newly started nodes as idle in slurm
  echo "[INFO] Sleeping for 60 seconds to allow time for slurm to ping hosts..."
  sleep 60
  echo "[INFO] Marking nodes in Slurm as IDLE..."
  sinfo -p $PARTITION -ho %n | xargs -I {} sudo scontrol update NodeName="{}" State=RESUME
  echo "[INFO] Start operation complete. Nodes are now IDLE..."
  exit 0
fi

# Handle start operation w/ qty specified
if [[ "$ACTION" == "start" ]] && [[ -n "$QTY" ]]; then 
  echo "[INFO] Performing '$ACTION' operation on $QTY Slurm $PARTITION partition nodes..."
  hosts=$(sinfo -h -o %n -t down -p $PARTITION | head -n $QTY)
  if [[ -z $hosts ]]; then
    echo  "[ERROR] There are no hosts in a down state to start..."
    exit 1
  fi
  if [[ `echo $hosts | wc -w` -lt "$QTY" ]]; then
    echo "[WARNING] Can only start `echo $hosts | wc -w` hosts instead of the requested $QTY..."
  fi
  for i in $hosts
  do
    ociname=`cat /etc/hosts | grep "$i " | awk '{print $4}'`
    ocid+=" $(oci compute instance list --compartment-id $COMPARTMENT_OCID --display-name $ociname --auth instance_principal | jq -r .data[0].id)"
  done
    echo "[INFO] Starting nodes..."
    echo $ocid | tr " " "\n" | xargs -P 0 -I {} oci compute instance action --action START --instance-id {} --wait-for-state RUNNING --wait-interval-seconds 5 --auth instance_principal

  echo "[INFO] Sleeping for 60 seconds to allow time for slurm to ping hosts..."
  sleep 60
  echo "[INFO] Marking nodes in Slurm as IDLE..."
  echo $hosts | tr " " "\n" | xargs -I {} sudo scontrol update NodeName="{}" State=RESUME
  echo "[INFO] Start operation complete. `echo $hosts | wc -w` nodes are now IDLE..."
  exit 0
fi
