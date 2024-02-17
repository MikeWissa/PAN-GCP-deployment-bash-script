Here is a detailed README explaining the key parts of this script:
By Mike Wissa

## Background
Working for Fortinet, the gcp gcloud deployment manager is available in the github repo; however, the Palo Alto Networks PAN VM-Series doesn't publish the gcloud deployment; however, this deployment is available from within GCP deployment manager. This was my attempt to simplify the process of launching the PAN vm-series and provide the same ease of use experience that is baked into Fortinet.


This script is built around uses gcloud deployment-manage
```
gcloud deployment-manager deployments create vm-name --config=pan-vm-series-bundleX
```

# VPC Network Creation Script

This Bash script automates the creation of VPC networks, subnets, firewall rules, and VM instance deployment on Google Cloud.

## Features

- Prompts user for project ID, region, zone, IP ranges
- Checks if networks already exist, creates them if not
- Creates subnets in each network 
- Opens firewall rules to allow full access 
- Lists available VM images and prompts user to select one
- Allows user to provide SSH public key or use default
- Creates deployment manager config from template
- Deploys or updates stack with instance
- Prints public IP and waits for it to be reachable

## Usage

1. Download the script and config template

2. Run the script:

```
chmod +x add-pan-in-gcp.sh
./add-pan-in-gcp.sh
```

3. Follow the prompts to provide details like project ID, region, VM image etc.

4. The script will create the networks, deploy VM instance, and output its public IP.

5. Wait for the instance to fully boot and then SSH in as user "admin".

## Assumtions
You need to be logged into gcloud

## Implementation Details

- Uses gcloud CLI to create all infrastructure
- Leverages Deployment Manager to deploy VM instance
- Spinner function provides interactive feedback during long-running tasks
- Checks for existing resources before creating to allow re-running script
- Templatizes Deployment Manager config for easy customization
- Waits and retries connecting to VM public IP until online

## Customization

- Edit the config template `expanded-config.yaml` to customize VM properties
- Adjust IP ranges if needed
- Set default project/region/zone at top of script
- Change `admin` SSH user as required

# When you are done - Don't let the bills pile up
just do that.
```
chmod +x remove-existing-pan-in-gcp
./remove-existing-pan-in-gcp
```
