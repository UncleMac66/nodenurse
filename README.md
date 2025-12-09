# ./nodenurse.sh

Helper tool to test, diagnose, reboot, and tag unhealthy nodes in a slurm based GPU cluster. Specifically designed to work out of the box with GPU environments set up with [oci-hpc](https://github.com/oracle-quickstart/oci-hpc)

 It assists with:
- Health monitoring (fresh/latest health checks)
- Node actions (reboot, tag/unhealthy, remove)
- Running quick NCCL benchmarks
- Detailed inventory (identify nodes, check slurm/OCI status)
- Maintenance, state updates (drain, resume, down, reservations)
- Executing commands across nodes

### Prerequisites

- **Required Tools:** 
(These are all a part of a standard OCI-HPC stack installation)
  - `bash`, `ssh`, `scontrol`, `sinfo`, `sacct`, `sbatch`
  - `jq`, `wget`, `python3`, `sudo`
  - Oracle CLI (`oci`) configured for instance principal auth
  - `pdsh`, `parallel-ssh`, `ansible`
- **Cluster Config Files:**
  - `/opt/oci-hpc/conf/queues.conf`
  - `/etc/ansible/hosts` with correct `tenancy_ocid`

### Installation

```
cd ~
git clone https://github.com/UncleMac66/nodenurse.git
cd ~/nodenurse
```
### Update

```
# Just run a pull from where you've cloned the nodenurse repo at anytime to update to the latest version
git pull
```

### Help Page and Examples

```
Usage: ./nodenurse.sh [OPTION] [ARGUMENT]

Description:
  nodenurse.sh takes supplied nodename(s), or a list of nodenames in a hostfile and can run a variety of functions
  on them which can be helpful when troubleshooting an OCI-HPC Slurm based cluster.

Options:
  -h, help             Display this message and exit.
  -c, healthcheck      Run a fresh healthcheck on the node(s).
  -l, latest           Gather the latest healthcheck from the node(s).
  -t, tag              Apply the unhealthy tag to the node(s)
  setuptag             Setup tagging in tenancy
  -r, reboot           Hard reboot the node(s).
  -e, exec             Execute command on the node(s)
  -i, identify         Display full details of the node(s) and exit.
  -n, nccl             Run allreduce nccl test on the node(s).
  -s, ncclscout        Run ncclscout (nccl pair test) on the node(s).
  -u, update           Update the slurm state on the node(s).
  -v, validate         Run nodes through checks to ensure ansible scripts will work.
  captop               Run a report on capacity topology if tenancy is enabled for it
  remove               Generate the resize command to remove the given node(s)
  fwcheck              Run a nvidia firmware check on the node(s) (helpful for gpu bus issues)
  --version            Display the current version and exit.

Arguments:
HOST(S)                  An input hostfile, or space separated list of hostnames (e.g. gpu-1 gpu-2) or slurm notation like gpu-[1,2,5-6].

  --all                  Use all hosts that are listed in slurm.

  --idle                 Use hosts that are in a 'idle' state in slurm.

  --drain                Use hosts that are in a 'drain' state in slurm.

  --down                 Use hosts that are in a 'down' state in slurm.

  --alldown              Use hosts that are in a 'down' or 'drain' state in slurm.

  --maint                Use hosts that are in a 'maint' state in slurm.

  --partition,-p <name>  Use all nodes in a specified slurm partition name (i.e. compute).

  --quiet                Remove confirmations and warnings to allow for running without user input
                         (Only works on options that don't explicitly ask for options like reboot)

Examples:
  ./nodenurse.sh healthcheck <path/to/hostfile>    runs a fresh healthcheck on the node(s) in the provided hostlist.
  ./nodenurse.sh reboot gpu-1                      sends a hard reboot signal to node 'gpu-1'.
  ./nodenurse.sh validate --all                    validates all nodes
  ./nodenurse.sh exec -p compute                   starts a remote execution prompt using all nodes in the 'compute' slurm partition
  ./nodenurse.sh latest --alldown                  grabs the latest healthchecks from nodes marked as drain or down in slurm.
  ./nodenurse.sh identify gpu-1 gpu-2              display details about 'gpu-1' and 'gpu-2' then quit.
  ./nodenurse.sh -c gpu-[1,2] --quiet              run a fresh healthcheck on 'gpu-1' and 'gpu-2' without confirmations then quit.

Notes:
  - nodenurse.sh gets compartment OCID from /opt/oci-hpc/conf/queues.conf.
    If you use queues across compartments please double check this value.

  - In order for tagging hosts as unhealthy to work properly, your tenancy must be properly
    whitelisted for unhealthy instance tagging.

  - nodenurse.sh deduplicates your provided hostlist.
```

### Examples with sample output

#### Healthcheck mode grabs the latest healthchecks from the OCI-HPC team and runs them in parrallel or sequentially across the nodelist

```
$ ./nodenurse.sh healthcheck --all --quiet

Fresh Healthcheck Mode...

Filtering all hosts from slurm...

Quiet mode activated

----------------------------------------------------------------
---------------------- 2025-08-29 16:30:08 ---------------------
----------------------------------------------------------------

Hostname                  Instance Name             Slurm State

gpu-346                   inst-wswc-dev             idle
gpu-524                   inst-x9f2-dev             idle
gpu-569                   inst-utr4-dev             idle

Total: 3 Distinct host(s)


Note: To keep output brief, only reporting on errors and warnings

----------------------------------------------------------------
Output from nodes: gpu-346 gpu-524 gpu-569
----------------------------------------------------------------


Complete: Healthchecks gathered on 3 nodes
```

#### Remove mode generates the correct resize.sh command for you to run on a given set of nodes

```
$ ./nodenurse.sh remove gpu-[280,609,834]

Remove Mode...

----------------------------------------------------------------
---------------------- 2025-08-28 16:31:18 ---------------------
----------------------------------------------------------------

Hostname                  Instance Name             Slurm State

gpu-280                   inst-lef-iad-h100         mix
gpu-609                   inst-ieq-iad-h100         mix
gpu-834                   inst-mep-iad-h100         mix

Total: 3 Distinct host(s)

Resize command:

/opt/oci-hpc/bin/resize.sh remove --nodes inst-lef-iad-h100 inst-ieq-iad-h100 inst-mep-iad-h100  --cluster_name iad-h100
```

#### Quiet mode, hushes all the confirmation prompts so you can include nodenurse cmds in cronjobs and the like.

```
./nodenurse.sh validate -p compute --quiet 
```
or
```
$ ./nodenurse.sh -c -p compute --quiet

Fresh Healthcheck Mode...

Filtering hosts from slurm marked as 'down' and 'drain'...

Quiet mode activated

----------------------------------------------------------------
---------------------- 2025-08-28 16:34:21 ---------------------
----------------------------------------------------------------

Hostname                  Instance Name             Slurm State

gpu-1022                 inst-bw-iad-gpu            down*
gpu-104                  inst-1v-iad-gpu            down*
```

#### Reboot mode issues a hard reset command to all the nodes in the given node list.

```
$ ./nodenurse.sh reboot gpu-[346,524]

Reboot Mode...

----------------------------------------------------------------
---------------------- 2025-08-29 16:45:39 ---------------------
----------------------------------------------------------------

Hostname                  Instance Name             Slurm State

gpu-346                   inst-wdswc-dev            idle
gpu-524                   inst-x9lf2-dev            idle

Total: 2 Distinct host(s)

Are you sure you want to force reboot the node(s)? (yes/no/quit)
yes

----------------------------------------------------------------
Rebooting gpu-346
Instance Name: inst-wdswc-dev    
Serial Number: Not Specified
OCID: ocid1.instance.oc1.iad.anuwcljtbjr2exacgwlsfi7kq2oy2fa7h3ecluvjs3gr2pq6zvpfq

202508291645 - Success - Hard reset sent to node gpu-346
----------------------------------------------------------------


----------------------------------------------------------------
Rebooting gpu-524
Instance Name: inst-x9lf2-dev    
Serial Number: Not Specified
OCID: ocid1.instance.oc1.iad.anuwcljtbjr2exac3azyxrc6lwbo4v4wfq4j7wb3kmwrevn22q

202508291646 - Success - Hard reset sent to node gpu-524
----------------------------------------------------------------
```