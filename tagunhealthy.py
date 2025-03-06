#!/usr/bin/env python3

import oci
import argparse

argparser = argparse.ArgumentParser()
argparser.add_argument('--instance-id', help='The OCID of the instance to tag', required=True)
argparser.add_argument('--region', help='Region')
args = argparser.parse_args()

signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()

if args.region:
    region = args.region
else:
    region = signer.region
config = {'region': region, 'tenancy': signer.tenancy_id}

# Initialize the OCI ComputeClient
compute_client = oci.core.ComputeClient(config, signer=signer)
compute_composite = oci.core.ComputeClientCompositeOperations(compute_client)
compute_management = oci.core.ComputeManagementClient(config, signer=signer)
compute_management_composite = oci.core.ComputeManagementClientCompositeOperations(compute_management)

instance_ocid = args.instance_id

try:
    instance = compute_client.get_instance(instance_id=instance_ocid).data
    tags = instance.defined_tags
    tags.update({'ComputeInstanceHostActions': { 'CustomerReportedHostStatus': 'unhealthy' }})
    update_instance_details = oci.core.models.UpdateInstanceDetails(defined_tags=tags)
    print(f"Updating tags on instance: {instance_ocid}")
    compute_client.update_instance(instance_id=instance_ocid, update_instance_details=update_instance_details)

except oci.exceptions.ServiceError as e:
    print(f"Error: {e}")

