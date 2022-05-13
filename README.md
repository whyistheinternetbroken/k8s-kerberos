# k8s-kerberos
This is a Kubernetes deployment of NFSv4.1 Kerberos with mount in privileged container and user access from an unprivileged container.

The environment consists of the following:

- Active Directory DC for DNS/KDC/LDAP services
- GKE Kubernetes deployment of 3 nodes
- Custom containers running ngnix
- Configuration files to modify for specific environments
- SSSD LDAP on the clients for usernames/groupnames
- NFS server/volume running in Google Cloud using NetApp Cloud Volume Services https://cloud.google.com/architecture/partners/netapp-cloud-volumes

For an on-prem version of this setup, use:
https://github.com/whyistheinternetbroken/ubuntu20-NFS-kerberos

**Kubernetes Node Config**

1) Create the GKE cluster
2) Create a machine account object in AD and associated DNS entry
3) Create a keytab file from that account using ktpass on the ADDC.

The following is the syntax I used:

C:\> ktpass -princ primary/instance@REALM -mapuser DOMAIN\machine$ -crypto AES256-SHA1 +rndpass -ptype KRB5_NT_PRINCIPAL +Answer -out [file:\location]

4) Copy the keytab to each of your Kubernetes cluster nodes as /etc/krb5.keytab. Test that the keytab is readable with: klist -kte

This is an example of what the command output would look like:

$ sudo klist -kte
Keytab name: FILE:/etc/krb5.keytab
KVNO Timestamp         Principal
---- ----------------- --------------------------------------------------------
   3 01/01/70 00:00:00 root/nfs-poc-privile.cvsdemo.local@CVSDEMO.LOCAL (aes256-cts-hmac-sha1-96)
   
5) Modify /etc/idmapd.conf on each Kubernetes node

This is what the file contents would look like:

[General]

Domain = YOURDOMAIN.COM

You can check to see if the domain is set with the following:

$ sudo nfsidmap -d
YOURDOMAIN.COM

6) Modify the /etc/request-key.d/id_resolver.conf on each node to include the following line:

create  id_resolver     *       *       /usr/bin/run_in_sssd_container /usr/sbin/nfsidmap -t 600 %k %d


**Container configuration**

There will be two containers used here. 

- a privileged container and handles the NFS Kerberos mount and includes SSSD configuration
- an unprivileged container that will handle the actual user access to the mount

The privileged container dockerfile can be found here:

https://github.com/whyistheinternetbroken/k8s-kerberos/blob/main/privileged-container.dockerfile

The unprivileged container dockerfile can be found here:

https://github.com/whyistheinternetbroken/k8s-kerberos/blob/main/unprivileged-container.dockerfile

I had to build each container and then push them up to the Docker hub to allow the pods to create properly. There are ways to localize the containers, but I did not explore doing that.

In the folder with the dockerfiles, I have the following configuration files/scripts:

* bashrc - this allows the NFS configuration script to run when the privileged container is executed using bash
* configure-nfs.sh - this script checks if services are started and starts them if needed and also will mount the NFS Kerberos mount. This is run with the privileged container.
* fstab - this file specifies the NFS mount path for the privileged container
* idmapd.conf - this file contains the NFSv4 ID mapping configuration (domain, nobody user/group); modify for your specific environment
* krb5.conf - this file configures the Kerberos realm information for the containers; modify for your specific environment
* restart-sssd.sh - this script restarts the SSSD service when the unprivileged container starts up 
* run_in_sssd_container - this script is used to allow SSSD to be used with NFSv4 mappings to populate the proper users/group owners on files and folders with NFSv4
* sssd.conf - this configures SSSD for the containers; modify for your specific environment
* unprivbashrc - this allows the SSSD restart script to run when the unprivileged container is executed using bash


**Pod YAML files**

These are the pod YAML files used for this deployment. 

Privileged pod:

https://github.com/whyistheinternetbroken/k8s-kerberos/blob/main/privileged-pod.yaml

Unprivileged pod:

https://github.com/whyistheinternetbroken/k8s-kerberos/blob/main/unprivileged-pod.yaml

This is how the pods should be created/run.

1) kubectl create -f privileged-pod.yaml
2) kubectl get pods (to confirm the pod is running)
3) kubectl exec -it privileged-pod -- configure-nfs.sh (this starts the necessary services and mounts NFS Kerberos)
4) kubectl create -f unprivileged-pod.yaml (don't create this until you've confirmed the privileged pod has started properly)
5) kubectl get pods (to confirm the pod is running)
6) kubectl exec -it unprivileged-pod -- bash

Once in the unprivileged pod, check that usernames can be queried via SSSD (id username) and that you can su/kinit with:

ksu username -n username

This will drop you into your user's shell and you should have a new Kerberos ticket. Then, try to access the mount.

NOTE: If you delete the privileged pod, be sure to enter bash and unmount the NFS mount first. Otherwise, new pod create commands will fail. If you forget to unmount in the container before deleting the pod, then log into the Kubernetes node and unmount the NFS mount there.

**Example**

parisi@cloudshell:~$ kubectl create -f privileged-pod.yaml 
pod/nfs-poc-privileged created
parisi@cloudshell:~$ kubectl get pods
NAME                 READY   STATUS    RESTARTS   AGE
nfs-poc-privileged   1/1     Running   0          6s

parisi@cloudshell:~$ kubectl exec -it nfs-poc-privileged -- configure-nfs.sh
Stopping NFS common utilities: gssd idmapd statd.
Starting NFS common utilities: statd idmapd gssd.
Stopping NFS common utilities: gssd idmapd statd.
Starting NFS common utilities: statd idmapd gssd.
Stopping NFS common utilities: gssd idmapd statd.
Starting NFS common utilities: statd idmapd gssd.
/nfs is not mounted. Mounting /nfs...
Mount success!

parisi@cloudshell:~$ kubectl create -f unpriv-pod.yaml
pod/nfs-poc-unprivileged created
parisi@cloudshell:~$ kubectl get pods
NAME                   READY   STATUS    RESTARTS   AGE
nfs-poc-privileged     1/1     Running   0          66s
nfs-poc-unprivileged   1/1     Running   0          3s

parisi@cloudshell:~$ kubectl exec -it nfs-poc-unprivileged -- bash
root@nfs-poc-unprivileged:/# id parisi
uid=1019(parisi) gid=1020(parisigroup) groups=1020(parisigroup),513(domain users)
root@nfs-poc-unprivileged:/# ksu parisi -n parisi
Changing uid to parisi (1019)
bash: /home/parisi/.bashrc: Key has expired
parisi@nfs-poc-unprivileged:/$ kinit
Password for parisi@CVSDEMO.LOCAL:
parisi@nfs-poc-unprivileged:/$ klist
Ticket cache: FILE:/tmp/krb5cc_1019.hnXlZKVV
Default principal: parisi@CVSDEMO.LOCAL

Valid starting     Expires            Service principal
05/13/22 12:40:32  05/13/22 22:40:32  krbtgt/CVSDEMO.LOCAL@CVSDEMO.LOCAL
        renew until 05/20/22 12:40:29
        
parisi@nfs-poc-unprivileged:/$ cd /home
parisi@nfs-poc-unprivileged:/home$ klist
Ticket cache: FILE:/tmp/krb5cc_1019.hnXlZKVV
Default principal: parisi@CVSDEMO.LOCAL

Valid starting     Expires            Service principal
05/13/22 12:40:32  05/13/22 22:40:32  krbtgt/CVSDEMO.LOCAL@CVSDEMO.LOCAL
        renew until 05/20/22 12:40:29
05/13/22 12:40:40  05/13/22 22:40:32  nfs/nfsserver.cvsdemo.local@CVSDEMO.LOCAL
        renew until 05/20/22 12:40:29
