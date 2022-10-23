#!/bin/bash

clear

config_file="/etc/mpi-config.conf"
head_ip=$( ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}' )
cluster_names=()
cluster_ips=()

# Checks if program is running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this program as root"
    exit
fi

# Function to write config file
function set_config(){
    sudo sed -i "s/^\($1\s*=\s*\).*\$/\1$2/" $config_file
    source "$config_file"
}

# Function to join an array into one string
join_array() {
    local IFS="$1"
    # shift
    echo "$*"
}

# Checks for debug arguments
if [ "$1" == "-r" ] || [ "$1" == "-d" ]; then
    sudo rm $config_file
fi

# Generates an empty config file to /etc/mpi-config,
# removes and regenerates if it is run with the
# regenerate parameter
generate_config() {
    
    sudo touch $config_file
    
    sudo echo "cluster_name=''"  >> $config_file
    sudo echo "cluster_size=" >> $config_file
    sudo echo "node_names=" >> $config_file
    sudo echo "node_ips=" >> $config_file
    sudo echo "changed_hosts=0" >> $config_file
    sudo echo "mpi_username=''" >> $config_file
    sudo echo "user_set=0" >> $config_file
    sudo echo "nfs_set=0" >> $config_file
    sudo echo "ssh_set=0" >> $config_file
    sudo echo "mpi_set=0" >> $config_file
    sudo echo "mpi_distribution=''" >> $config_file
    sudo echo "setup_complete=0" >> $config_file
    sudo echo "setup_working=0" >> $config_file
    
    sleep 0.5
    
    echo -e "Empty config file generated! \n"
    
}

# Checks if a config file has been generated by program,
# if not it generates an empty one to /etc/mpi-config.conf
if [ ! -f "$config_file" ]; then
    echo "Generating empty config file..."
    generate_config
fi

# Source the config file
source "$config_file"

echo -e "Welcome to Pleiades MPI installer version 0.2! \n"


DONE=false

# Main setup loop
while [ "$DONE" = false ] && [ "$setup_complete" = "0" ]; do
    
    # User inputs name for cluster
    read -p "Enter a name for your cluster: " name
    set_config cluster_name $name
    
    
    read -p "How many nodes would you like to connect?: " number_of_nodes
    echo
    
    re='^[0-9]+$'
    
    while [ -z $number_of_nodes ] || [[ ! $number_of_nodes =~ $re ]]; do
        
        echo "Error cannot be empty"
        read -p "How many nodes would you like to connect?: " number_of_nodes
        
    done
    
    # Sets config file variable
    set_config cluster_size $number_of_nodes
    source "$config_file"
    # echo $cluster_size
    
    
    # IP address user input loop, only as many as the user specified
    for ((i=1; i<=$number_of_nodes; i++))
    do
        # The first iteration must be the head node or localhost
        if [ $i -eq 1 ]; then
            
            while [ -z $head_ip ]
            do
                echo "Fatal error. Head node has no IP"
                exit 1
            done
            
            cluster_names+=($HOSTNAME)
            cluster_ips+=($head_ip)
            
        fi
        
        # User inputs node name
        read -p "Enter the name that will be associated to your node, no spaces: " slave_name
        while [ -z "$slave_name" ]; do
            echo "Error cannot be empty"
            read -p "Enter the identification that will be associated to your node: " slave_name
        done
        
        while [[ "$slave_name" =~ " " ]]; do
            echo "Error cannot have spaces"
            read -p "Enter the identification that will be associated to your node: " slave_name
        done
        
        
        # The next iterations must be the nodes that will connect to the localhost
        read -p "Enter the IP of your slave node number $i: " slave_ip
        
        while [ -z "$slave_ip" ]; do
            echo "Error cannot be empty"
            read -p "Enter the IP of your slave node number $i: " slave_ip
        done
        echo "Pinging..."
        ping -c1 $slave_ip 1>/dev/null 2>/dev/null
        SUCCESS=$?
        
        while [ $SUCCESS -ne 0 ]
        do
            
            echo "Ping from $IP was not successful, please try again"
            read -p "Enter the IP of your slave node number $i: " slave_ip
            
            ping -c1 $slave_ip 1>/dev/null 2>/dev/null
            SUCCESS=$?
            
        done
        
        echo "Ping from $slave_ip successful!"
        echo
        
        cluster_ips+=($slave_ip)
        cluster_names+=($slave_name)
        
    done
    
    
    # Joins the arrays with the cluster data, and serializes it to config file
    node_ips_string=$(join_array  ,"${cluster_ips[@]}")
    # echo "join_array :: $node_ips_string"
    set_config node_ips $node_ips_string
    node_names_string=$(join_array  ,"${cluster_names[@]}")
    # echo "join_array :: $node_names_string"
    set_config node_names $node_names_string
    
    # cluster_names=( "${cluster_names[@]/' '} " )
    # cluster_ips=( "${cluster_ips[@]/' '} " )
    
    # Generates a hosts file
    hosts_file="hosts"
    touch $hosts_file
    
    echo -e "127.0.0.1 \t localhost" >> $hosts_file
    
    for index in ${!cluster_names[*]}; do
        echo -e "${cluster_ips[$index]} \t ${cluster_names[$index]}" >> $hosts_file
    done
    
    echo -e "\n# The following lines are desirable for IPv6 capable hosts " >> $hosts_file
    echo "::1     ip6-localhost ip6-loopback" >> $hosts_file
    echo "fe00::0 ip6-localnet" >> $hosts_file
    echo "ff00::0 ip6-mcastprefix" >> $hosts_file
    echo "ff02::1 ip6-allnodes" >> $hosts_file
    echo "ff02::2 ip6-allrouters" >> $hosts_file
    
    # Creates a backup folder for the user's old hosts file
    if [ ! -d "./backup" ]; then
        mkdir backup
    fi
    
    rm ./backup/hosts
    sudo mv /etc/hosts ./backup/hosts
    sudo mv $hosts_file /etc/
    
    echo -e "/etc/hosts file generated and updated! A backup was copied to the backup folder \n"
    
    set_config changed_hosts 1
    
    sudo cp $config_file ./backup/
    
    # echo $mpi_username
    
    mpi_user="mpiuser"
    
    echo -e "Which profile name would you like to use for your mpi user? "
    echo -e "\t 1) $mpi_user \n \t 2) $cluster_name \n \t 3) Other"
    
    read -p "Profile name[1]: " user_selection
    
    
    if [ "$user_selection" == "2" ]; then
        
        set_config mpi_username $cluster_name
        # echo "Set username to $cluster_name"
        
        elif [ "$user_selection" == "3" ]; then
        
        read -p "Enter your preferred mpi profile name: " user_name
        
        
        while [ -z "$user_name" ]; do
            
            echo "Error cannot be empty"
            read -p "Enter your preferred mpi profile name, no spaces: " user_name
            
        done
        
        while [[ "$user_name" =~ " " ]]; do
            
            echo "Error cannot have spaces"
            read -p "Enter your preferred mpi profile name, no spaces: " user_name
            
        done
        
        set_config mpi_username $user_name
        # echo "Set username to $user_name"
        # echo $mpi_username
    else
        
        set_config mpi_username $mpi_user
        # echo "Set username to $mpi_user"
        # echo $mpi_username
        
    fi

    echo
    
    if [ "$1" == "-d" ]; then
        
        cat /etc/hosts
        echo
        cat $config_file
        echo
        echo "Script terminated"
        
        
    fi
    
    
    
    exit 0
    
    
done