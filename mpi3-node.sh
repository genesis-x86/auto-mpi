#!/bin/bash

# Checks if netcat is installed, if not it installs it. Skips if ran with -i argument
if [ "$#" == "-i" ]; then
    if [ "$(dpkg-query -W --showformat='${Status}\n' netcat|grep "install ok installed" )" == "install ok installed" ]; then
        
        echo -e "Installing dependencies..."
        sudo apt-get update -y >/dev/null
        sudo apt-get install netcat -y >/dev/null
        echo "Done!"
        
    fi
    
    # Checks if nfs-common is installed, if not it installs is
    if [ "$(dpkg-query -W --showformat='${Status}\n' nfs-common|grep "install ok installed" )" == "install ok installed" ]; then
        
        echo -e "Installing dependencies..."
        sudo apt-get update -y >/dev/null
        sudo apt-get install nfs-common -y >/dev/null
        echo "Done!"
        
    fi
fi

# Creates a backup folder for all files being replaced
if [ ! -d "./backup" ]; then
    mkdir backup
fi

function split_file(){
    delta_split=0
    touch ./backup/mpi-config.conf
    touch ./backup/hosts
    
    while read -r line; do
        
        echo $line
        
        if [ "$delta_split" == "1" ]; then
            
            sudo echo "$line" >> ./backup/hosts
            
            elif [ "$line" != "$2" ] && [ "$delta_split" == "0" ]; then
            
            sudo echo "$line" >> ./backup/mpi-config.conf
            
            elif [ "$line" == "$2" ] && [ "$delta_split" == "0" ]; then
            
            delta_split=1
            
        fi
        
        
    done <$1
    
    if test -f /etc/hosts; then
        sudo rm /etc/hosts
    fi
    
    sudo mv ./backup/hosts /etc/
    sudo mv ./backup/mpi-config.conf /etc/
    
}

# Function to copy and move a specific file to /backup folder and put
# another file in its place
function move_file(){
    sudo mv $1 ./backup/$2
    sudo mv $3 $4
}

if [ "$1" == "-ng" ] && [ -n $2 ] && [ -n $3 ]; then
    
    ping -w 1 -c 1 $2 > /dev/null
    SUCCESS=$?
    
    # echo $SUCCESS
    
    if [ "$SUCCESS" != "0" ]; then
        echo "Error: IP cannot be reached"
        exit
    fi
        
    PORT=$3
    
else
    
    echo -e "Welcome to Pleiades Node installer version 0.3! \n"
    
    read -p "Enter the IP of your Master node: " IP
    
    echo "Pinging..."
    ping -c1 $slave_ip 1>/dev/null 2>/dev/null
    SUCCESS=$?
    # echo $SUCCESS
    
    while [ $SUCCESS -eq 0 ]
    do
        
        echo "Ping from $IP was not successful, please try again"
        read -p "Enter the IP of your Master node: " IP
        
        ping -c2 $slave_ip 1>/dev/null 2>/dev/null
        SUCCESS=$?
        
    done
    
    echo -e "Ping from $IP successful! \n"
    read -p "Enter the port that the Master is transmitting on[1000]: " PORT
    
    if [ -z $PORT ]; then
        
        PORT=1000
        
    fi
        
fi

transfer_file="./backup/transfer"

sudo rm $transfer_file

echo "Listening..."
sudo netcat -l $PORT > $transfer_file

if test -f $transfer_file; then
    
    #move_file /etc/hosts hosts "hosts" /etc/
    # source "./backup/transfer"
    echo -e "\nSuccessfully copied configuration from MASTER!"
else
    
    echo "Error: No file recieved"
    
fi

# Splits the transferred file, and moves the new files to /etc/mpi-config-conf and /etc/hosts
split_file $transfer_file "#"

# Sources the newly transferred config file. Now the head and the nodes have the same file, but
# how can we make sure they have parity throughout the execution of the scripts?
source /etc/mpi-config.conf

# Creates an array with string of node names inside the config file. Must be converted since 
# the config can't have arrays for some reason.
node_names_array=(${node_names//,/ })
echo "DEBUG :: NODE NAMES: ${node_names_array[@]}"

sudo useradd -m "$mpi_username"
# Needs a password to be set!!!

sudo mount ${node_names_array[0]}:/home/$mpi_username /home/$mpi_username

# Sends config file out to head node to check for parity
echo "Transmitting parity check on port: $PORT "
sudo netcat -w 2 ${node_names_array[0]} $PORT < "/etc/mpi-config"

# Edits /etc/fstab file so the nodes mount to the head node at startup
echo "sudo mount ${node_names_array[0]}:/home/$mpi_username /home/$mpi_username" | sudo tee -a /etc/fstab


exit




if [ "$1" == "-d" ]; then
    
    sudo apt-get purge nfs-common -y
    
fi