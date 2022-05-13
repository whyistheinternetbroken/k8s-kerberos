#!/bin/bash
###########################
# Define script variables #
###########################

idmap_pid=$(pgrep -x rpc.idmapd)
rpcbind_pid=$(pgrep -x rpcbind)
gss_pid=$(pgrep -x rpc.gssd)
statd_pid=$(pgrep -x rpc.statd)

RPCBIND_PATH=/sbin/rpcbind
IDMAP_PATH=/usr/sbin/rpc.idmapd
NFS_RESTART="service nfs-common restart"
GSS_PATH=/usr/sbin/rpc.gssd

mount="/nfs"
mountpath="/twosigmakrb"

### change perms for SSSD script

sudo chmod +x /usr/bin/run_in_sssd_container

### restart processes as needed

if [ -z $rpcbind_pid ] ; then
    $RPCBIND_PATH
else
    echo "rpcbind is running"
fi

if [ -z $statd_pid ] ; then
    $NFS_RESTART
else
    echo "statd is running"
fi

if [ -z $idmap_pid ] ; then
    $NFS_RESTART
else
    echo "rpc.idmapd is running"
fi

if [ -z $gss_pid ] ; then
    $NFS_RESTART
else
    echo "rpc.gssd is running"
fi

sudo service sssd restart

if grep -qs "$mountpath" /proc/mounts; then
  echo "/nfs is mounted."
else
  echo "/nfs is not mounted. Mounting /nfs..."
  mount "$mount"
  if [ $? -eq 0 ]; then
   echo "Mount success!"
  else
   echo "Something went wrong with the mount..."
  fi
fi
