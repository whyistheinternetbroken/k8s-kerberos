FROM nginx:1.21.6
ENV container docker

# Attach rpc_pipefs
RUN mkdir -p /run/rpc_pipefs
VOLUME /run/rpc_pipefs

# Update client/install packages
RUN apt-get update && apt-get install -y sudo apt-utils
RUN apt-get update && apt-get autoremove
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -qq -y nfs-common krb5-user sssd* ntp *-sss vim procps

# Copy the local SSSD conf file
RUN mkdir -p /etc/sssd
COPY sssd.conf /etc/sssd/sssd.conf
RUN chmod 600 /etc/sssd/sssd.conf

# Copy the fstab file
COPY fstab /etc/fstab

# Copy the local krb files
COPY krb5.conf /etc/krb5.conf

# Copy the NFSv4 IDmap file
COPY idmapd.conf /etc/idmapd.conf

#COPY run_in_sssd script
COPY run_in_sssd_container /usr/bin/run_in_sssd_container
# Script to start services
COPY bashrc /root/.bashrc
COPY configure-nfs.sh /usr/local/bin/configure-nfs.sh
RUN chmod +x /usr/local/bin/configure-nfs.sh
