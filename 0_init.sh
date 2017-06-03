#!/bin/bash -e

touch .hushlogin

# echo "uptime && free -m" > /etc/profile.d/login.sh
# chmod +x /etc/profile.d/login.sh
# ssh-keygen -t rsa -b 2048 -N ""

# for security.ubuntu.com - doesn't like ipv6
echo -e '\nprecedence ::ffff:0:0/96 100\n' >> /etc/gai.conf

apt-get update
apt-get -y upgrade

locale-gen --purge en_US.UTF-8
echo -e 'LANG=en_US.UTF-8\n' > /etc/default/locale

apt-get -y install screen sudo ufw
