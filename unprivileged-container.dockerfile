FROM nginx:1.21.6
ENV container docker
ENV LC_ALL C
ENV TZ=US/Eastern

# Update client/install packages
RUN apt-get update && apt-get install -y sudo apt-utils
RUN apt-get update && apt-get autoremove
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get install -qq -y krb5-user sssd* ntp *-sss vim net-tools dnsutils

# Copy the local SSSD conf file
RUN mkdir -p /etc/sssd
COPY sssd.conf /etc/sssd/sssd.conf

# Copy the local krb files
COPY krb5.conf /etc/krb5.conf

# Copy the NFSv4 IDmap file
COPY idmapd.conf /etc/idmapd.conf

#COPY run_in_sssd script
COPY run_in_sssd_container /usr/bin/run_in_sssd_container

# Script to start services
COPY unprivbashrc /root/.bashrc
COPY restart-sssd.sh /usr/local/bin/restart-sssd.sh
RUN chmod +x /usr/local/bin/restart-sssd.sh
