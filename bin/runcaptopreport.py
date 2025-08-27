#!/usr/bin/python3
import oci
from datetime import datetime
import argparse
import sys

argparser = argparse.ArgumentParser()
argparser.add_argument('--capacity-id', help='The OCID of the Capacity Topology to user')
args = argparser.parse_args()

capacity_topology_id = args.capacity_id
signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
computeClient = oci.core.ComputeClient(config={}, signer=signer)


count=0
repair_nodes=[]

try:
    print(datetime.now().strftime("%m/%d/%Y %H:%M:%S"))
    print("----------------------\n     Block Status\n----------------------")
    response=oci.pagination.list_call_get_all_results(computeClient.list_compute_capacity_topology_compute_bare_metal_hosts, capacity_topology_id)
    state_counts={}
    for node in response.data:
        shape=node.instance_shape
        status=node.lifecycle_details
        count+=1
        if status == "AVAILABLE" :
            if node.instance_id:
                status="RUNNING"
            else:
                status="AVAILABLE"

        if status == "UNAVAILABLE" or status == "DEGRADED" :
            if node.instance_id:
                status="RUNNING"
            else:
                status="IN_REPAIR"
                repair_nodes.append({ "id":node.id })

        if status in state_counts.keys():
            state_counts[status]+=1
        else:
            state_counts[status]=1
    print("State :: "+str(state_counts)+"\n")
    print("Total ::", count, shape)

    if len(repair_nodes) > 0:
        print("-----------------------------------\n      Nodes in Repair\n-----------------------------------")
        for i in repair_nodes:
            print(i)


except Exception as e:
    sys.exit(1)


