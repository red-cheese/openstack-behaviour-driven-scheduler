#!/bin/bash

# list of openstack guests
vmlist=`nova-manage vm list 2>/dev/null | grep active | tr -s \  | cut -d \  -f 1`

# list of openstack hosts
hostlist=`nova-manage host list 2>/dev/null | grep nova | cut -d \  -f 1`

# maps to match openstack guest name to libvirt name to pid to pcpu
declare -A libvirt_to_nova_map
declare -A pid_to_pcpu_map
declare -A pid_to_libvirt_map

# fill libvirt to nova names mapping
for name in $vmlist
do
    instance=`nova show $name | grep  instance_name | tr -s \  | cut -d \  -f 4`
    libvirt_to_nova_map[$instance]=$name
done


# fill name,host,time,pcpu records
for host in $hostlist
do
    # number of processors is needed to correct pcpu from 'top' - it shows pcpu per core
    proc_num=`ssh $host grep 'processor' /proc/cpuinfo | wc -l`

    # find all guest processes and their pids
    pid_to_libvirt_map=()
    pid_instance_list=`ssh $host ps -o pid=,args= -C qemu-system-x86_64 | grep 'name' | sed -E 's/^[ ]*([0-9]+) .* -name ([A-Za-z0-9-]+) .*/\1=\2/g'`
    for pid_instance_pair in $pid_instance_list
    do
        set -- `echo $pid_instance_pair | tr '=' ' '`
        pid_to_libvirt_map[$1]=$2
    done

    # find pcpu for guest pids
    pid_to_pcpu_map=()
    pids=`echo ${!pid_to_libvirt_map[@]} | tr ' ' ','`
    [[ "x" = "x$pids" ]] && continue
    pid_pcpu_list=`ssh $host top -b -n 1 -p $pids | sed -E 's/^[ ]*//' | tr -s \  | cut -d \  -f 1,9 | tr ' ' '='`
    for pid_pcpu_pair in $pid_pcpu_list
    do
        set -- `echo $pid_pcpu_pair | tr '=' ' '`
        pid_to_pcpu_map[$1]=$2
    done

    # intersect maps
    for pid in ${!pid_to_libvirt_map[@]}
    do
        instance=${pid_to_libvirt_map[$pid]}
        name=${libvirt_to_nova_map[$instance]}
        pcpu=${pid_to_pcpu_map[$pid]}
        # correct pcpu - round and divide by number of virtual processors (sockets x cores x threads)
        pcpu=`echo $pcpu | tr \ '.' ' ' | cut -d \  -f 1`
        pcpu=$(( $pcpu / $proc_num ))
        [[ "x" != "x$instance" ]] && [[ "x" != "x$name" ]] && [[ "x" != "x$pcpu" ]] || continue
        echo $host $name $pcpu `date +%s`
    done
done

