#!/bin/bash
# Created by Mike Wissa - for fun
# Function to display the spinner
touch error_output.log
error_output="error_output.log"
show_spinner() {
     local pid=$1  # Process ID of the background command
     local delay=0.1
     local spinstr='|/-\'
     local infotext="[ ] Executing command... "

     echo -n "$infotext"

     while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
         local temp=${spinstr#?}
         printf " [%c]  " "$spinstr"
         local spinstr=$temp${spinstr%"$temp"}
         sleep $delay
         printf "\b\b\b\b\b\b"
     done

     # Clear spinner after command completion
     printf " \b\b\b\b"
}
function check_error() {
    local status=$1

    if [ $status -ne 0 ]; then
        echo -e "\033[31mCommand failed with error:\033[0m"
        while IFS= read -r line; do
            echo -e "\033[31m$line\033[0m"
        done < $error_output
    else
        echo "Command completed!"
    fi

    # Clear the error file
    > $error_output
}

# Get project ID
current_project_id=$(gcloud config get-value project)
read -p "Enter project ID (current: $current_project_id): " project_id
project_id=${project_id:-$current_project_id}

# Prompt for zone
current_zone=$(gcloud config get-value compute/zone)
read -p "Enter zone (current: $current_zone): " zone
zone=${zone:-$current_zone}

# Prompt for region
current_region=$(gcloud config get-value compute/region)
read -p "Enter region (current: $current_region): " region
region=${region:-$current_region}

# Prompt for IP ranges
read -p "Enter IP range for external (default 172.17.1.0/24): " iprange_e
iprange_e=${iprange_e:-"172.17.1.0/24"}

read -p "Enter IP range for internal (default 172.17.2.0/24): " iprange_i
iprange_i=${iprange_i:-"172.17.2.0/24"}

read -p "Enter IP range for management (default 172.17.3.0/24): " iprange_m
iprange_m=${iprange_m:-"172.17.3.0/24"}


# Declare an associative array with network names as keys and their associated variables as values
declare -A NETWORKS
NETWORKS=(["external"]="external" ["internal"]="internal" ["mgmt"]="mgmt")
declare -A network_to_iprange
network_to_iprange=( ["external"]="iprange_e" ["internal"]="iprange_i" ["mgmt"]="iprange_m" )

# Iterate through each network name
for NETWORK_NAME in "${!NETWORKS[@]}"; do
    # Check if the network exists
    NETWORK_EXISTS=$(gcloud compute networks list --filter="name=${NETWORK_NAME}" --format="value(name)")
    # If the network doesn't exist, take action
    if [ -z "${NETWORK_EXISTS}" ]; then
        echo "Network ${NETWORK_NAME} does not exist."

        # Use the associated variable for this network
        IPRANGE_VAR="${network_to_iprange[$NETWORK_NAME]}"
        IP_RANGE_VALUE="${!IPRANGE_VAR}"
        gcloud compute networks create ${NETWORK_NAME} \
        --project=${project_id} \
        --subnet-mode=custom \
        --mtu=1460 \
        --bgp-routing-mode=regional  2> $error_output &
            pid=$!
            show_spinner $pid
            wait $pid
            check_error $?

        gcloud compute networks subnets create ${NETWORK_NAME} \
        --project=${project_id} \
        --range=${IP_RANGE_VALUE} \
        --stack-type=IPV4_ONLY \
        --network=${NETWORK_NAME} --region=${region} \
        --enable-private-ip-google-access \
        --enable-flow-logs \
        --logging-aggregation-interval=interval-5-sec \
        --logging-flow-sampling=0.5 \
        --logging-metadata=include-all  2> $error_output &
            pid=$!
            show_spinner $pid
            wait $pid
            check_error $?

        echo "The firewall rule would allow all ip addresses to connect to the management interface, please restrict it when you are done instantiating the VM"
        gcloud compute firewall-rules create "allow-all-${NETWORK_NAME}" \
        --direction=INGRESS \
        --priority=1000 \
        --network="${NETWORK_NAME}" \
        --action=ALLOW \
        --rules=all \
        --source-ranges=0.0.0.0/0  2> $error_output &
            pid=$!
            show_spinner $pid
            wait $pid
            check_error $?

    else
        echo "Network ${NETWORK_NAME} already exists."
    fi
done

read -p "Which bundle do you want (1, 2, or 3)? " BUNDLE_CHOICE

# Check if the input is 1, 2, or 3
if [[ "$BUNDLE_CHOICE" != "1" && "$BUNDLE_CHOICE" != "2" && "$BUNDLE_CHOICE" != "3" ]]; then
    echo "Invalid choice. Please select 1, 2, or 3."
    exit 1
fi

# Based on the bundle choice, set the filter
FILTER="bundle$BUNDLE_CHOICE"

# Filter and fetch the list of images from the project
IMAGES=$(gcloud compute images list --project=paloaltonetworksgcp-public --filter="${FILTER}" --format="value(NAME)")

# Check if IMAGES is empty
if [[ -z "$IMAGES" ]]; then
    echo "No images found for Bundle $BUNDLE_CHOICE."
    exit 1
fi

# Create a menu for the user to select from
PS3='Please select an image: '

select IMAGE in $IMAGES; do
    if [[ -n $IMAGE ]]; then
        echo "You selected: $IMAGE"
        # You can now use $IMAGE variable for your further tasks
        break
    else
        echo "Invalid selection"
    fi
done

read -p "Should I use the default ssh public key under .ssh/id_rsa.pub? (yes/no) " CHOICE

if [[ "$CHOICE" == "yes" ]]; then
    # Check if the default public key exists
    if [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        PUB_KEY=$(cat "$HOME/.ssh/id_rsa.pub" | sed 's/^ssh-rsa //')
        echo "Using the default public key:"
        echo "$PUB_KEY"
    else
        echo "The default public key doesn't exist!"
        exit 1
    fi
elif [[ "$CHOICE" == "no" ]]; then
    read -p "Please paste the public key you want to use: this requires you to copy everything after the ssh-rsa[space] make sure you remove the space - Enter Public Key" PUB_KEY
    echo "You provided the following public key:"
    echo "$PUB_KEY"
else
    echo "Invalid choice!"
    exit 1
fi


read -p "What do you want the device name to be? " DEVICE_NAME
DEVICE_NAME="${DEVICE_NAME,,}"
echo "You have chosen '$DEVICE_NAME' as the device name."

key_content=$(cat ~/.ssh/id_rsa.pub | sed 's/ssh-rsa //')
gcloud compute instances list --filter="name=${INSTANCE_NAME} region:us-central1" '--format=value(zone)'  2> $error_output &
    pid=$!
    show_spinner $pid
    wait $pid
    check_error $?

# Fetch zones from the specified region
ZONES=$(gcloud compute zones list --filter="region:( $region )" --format="value(name)")

# Check if no zones are available
if [ -z "$ZONES" ]; then
    echo "No zones available in the $REGION region."
    exit 1
fi

# Present zones to the user
echo "Available zones in the $REGION region:"
select ZONE in $ZONES; do
    if [[ -n $ZONE ]]; then
        echo "You selected zone: $ZONE"
        break
    else
        echo "Invalid selection"
    fi
done

# You can now use the $ZONE variable in your script

cp expanded-config.yaml expanded-deployed-config.yaml
sed -i "s/DEVICE_NAME/${DEVICE_NAME}/g" expanded-deployed-config.yaml
sed -i "s/SRC_IMAGE/${IMAGE}/g" expanded-deployed-config.yaml
sed -i "s|REPLACE_SSH|${PUB_KEY}|g" expanded-deployed-config.yaml
sed -i "s/REPLACE_PROJECT/${project_id}/g" expanded-deployed-config.yaml
sed -i "s/REPLACE_REGION/${region}/g" expanded-deployed-config.yaml
sed -i "s/REPLACE_ZONE/${ZONE}/g" expanded-deployed-config.yaml

read -p "What do you want your deployment name to be? " DEPLOYMENT_NAME
DEPLOYMENT_NAME="${DEPLOYMENT_NAME,,}"
# Check if the deployment exists
gcloud deployment-manager deployments describe $DEPLOYMENT_NAME

# $? is a special variable that holds the exit status of the last command executed
if [ $? -eq 0 ]; then
    # Deployment exists, so update it
    echo "Deployment exists. Updating..."
    gcloud deployment-manager deployments update $DEPLOYMENT_NAME --config=expanded-deployed-config.yaml
else
    gcloud deployment-manager deployments create $DEPLOYMENT_NAME --config=expanded-deployed-config.yaml
fi



# Get the zone where the instance is located
ZONE=$(gcloud compute instances list --filter="name:${DEVICE_NAME}" --format="value(zone)")

# Extract the public IP from the instance using the identified zone

PUBLIC_IP=$(gcloud compute instances describe ${DEVICE_NAME} --zone=${ZONE} --format=json | jq -r '.networkInterfaces[] | select(.name == "nic0") | .accessConfigs[0].natIP')
echo "Public IP of the mgmt interface: $PUBLIC_IP"
COUNT=0          # Counter for ping attempts
MAX_RETRIES=999

while true; do
  if ping -c 1 $PUBLIC_IP > /dev/null 2>&1; then
    echo "Instance at IP $PUBLIC_IP is now responsive!"
    break
  else
    echo "Waiting for the instance at $PUBLIC_IP to start responding to pings"
    echo -n "#"
    COUNT=$((COUNT + 1))
  fi

  if [ $COUNT -eq $MAX_RETRIES ]; then
    echo "Max retries reached. Instance may be down or not reachable."
    break
  fi
  sleep 2
done
echo "Waiting for 5 minutes until the instance is fully provisioned, you can go grab a coffee, time for a break"
sleep 360
ssh-keygen -f ~/.ssh/known_hosts -R "${PUBLIC_IP}"
ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no -o StrictHostKeyChecking=accept-new -o HostKeyAlgorithms=ssh-rsa,ssh-ed25519 admin@${PUBLIC_IP}
