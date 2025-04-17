#!/bin/bash

# ------------------ CONFIGURATION ------------------
ACTION=$1
PARTITION="compute" # Replace with actual slurm partition
POOL_OCID="ocid1.instancepool.oc1.iad.aaaaaaaa"  # Replace with actual instance pool OCID
START_WAIT_TIME=60     # Adjust based on actual boot time
# ---------------------------------------------------

if [[ "$ACTION" != "start" && "$ACTION" != "stop" ]]; then
  echo "Usage: $0 start|stop"
  exit 1
fi

echo "[INFO] Performing '$ACTION' operation on Slurm $PARTITION partition nodes..."

# Handle stop operation
if [[ "$ACTION" == "stop" ]]; then
  echo "[INFO] Stopping $PARTITION instance pool..."
  oci compute-management instance-pool stop --instance-pool-id "$POOL_OCID" --auth instance_principal

# Mark stopped nodes as drain in slurm
  echo "[INFO] Marking nodes in Slurm as DRAIN..."
  sinfo -p $PARTITION -ho %n | xargs -I {} sudo scontrol update NodeName="{}" State=DOWN Reason="Manually Paused to stop billing"
  sleep 5

  echo "[INFO] Stop operation complete. Nodes are now DOWN."
fi

# Handle start operation
if [[ "$ACTION" == "start" ]]; then

  echo "[INFO] Starting $PARTITION instance pool..."
  oci compute-management instance-pool start --instance-pool-id "$POOL_OCID" --auth instance_principal

  echo "[INFO] Waiting for instances to start (sleeping $START_WAIT_TIME seconds)..."
  sleep $START_WAIT_TIME

# Mark newly started nodes as idle in slurm
  echo "[INFO] Marking nodes in Slurm as IDLE..."
  sinfo -p $PARTITION -ho %n | xargs -I {} sudo scontrol update NodeName="{}" State=RESUME
  sleep 5
  echo "[INFO] Start operation complete. Nodes are now IDLE."

fi
