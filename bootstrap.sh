#!/bin/bash

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Update software
echo "== Updating software"
apt-get update
apt-get dist-upgrade -y

apt-get install -y lsb-release apt-transport-https

# Add official Tor repository
if ! grep -q "https://deb.torproject.org/torproject.org" /etc/apt/sources.list; then
    echo "== Adding the official Tor repository"
    echo "deb https://deb.torproject.org/torproject.org $(lsb_release -cs) main" >> /etc/apt/sources.list
    wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import
    gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
    apt-get update
fi

# Install Tor and related packages
echo "== Installing Tor and related packages"
apt-get install -y tor tor-geoipdb tor-arm

# Stop Tor service
systemctl stop tor

# Configure Tor
cp $PWD/etc/tor/torrc /etc/tor/torrc

# Configure firewall rules
echo "== Configuring firewall rules"
apt-get install -y iptables-persistent
cp $PWD/etc/iptables/rules.v4 /etc/iptables/rules.v4
cp $PWD/etc/iptables/rules.v6 /etc/iptables/rules.v6
chmod 600 /etc/iptables/rules.v4
chmod 600 /etc/iptables/rules.v6
iptables-restore < /etc/iptables/rules.v4
ip6tables-restore < /etc/iptables/rules.v6

# Install fail2ban
apt-get install -y fail2ban

# Configure automatic updates
echo "== Configuring unattended upgrades"
apt-get install -y unattended-upgrades apt-listchanges
cp $PWD/etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
systemctl restart unattended-upgrades

# Install AppArmor
apt-get install -y apparmor apparmor-profiles apparmor-utils
sed -i.bak 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 apparmor=1 security=apparmor"/' /etc/default/grub
update-grub

# Install NTP
apt-get install -y ntp

# Install Monit
apt-get install -y monit
cp $PWD/etc/monit/conf.d/tor-relay.conf /etc/monit/conf.d/tor-relay.conf
systemctl restart monit

# Configure SSH
ORIG_USER=$(logname)
if [ -n "$ORIG_USER" ]; then
    echo "== Configuring SSH"
    # Only allow the current user to SSH in
    echo "AllowUsers $ORIG_USER" >> /etc/ssh/sshd_config
    echo "  - SSH login restricted to user: $ORIG_USER"
    if grep -q "Accepted publickey for $ORIG_USER" /var/log/auth.log; then
        # User has logged in with SSH keys so we can disable password authentication
        sed -i '/^#\?PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
        echo "  - SSH password authentication disabled"
        if [ $ORIG_USER == "root" ]; then
            # User logged in as root directly (rather than using su/sudo) so make sure root login is enabled
            sed -i '/^#\?PermitRootLogin/c\PermitRootLogin yes' /etc/ssh/sshd_config
        fi
    else
        # User logged in with a password rather than keys
        echo "  - You do not appear to be using SSH key authentication.  You should set this up manually now."
    fi
    systemctl reload ssh
else
    echo "== Could not configure SSH automatically.  You will need to do this manually."
fi

# Final instructions
echo ""
echo "== Try SSHing into this server again in a new window, to confirm the firewall isn't broken"
echo ""
echo "== Edit /etc/tor/torrc"
echo "  - Set Address, Nickname, Contact Info, and MyFamily for your Tor relay"
echo "  - Optional: include a Bitcoin address in the 'ContactInfo' line"
echo "    - This will enable you to receive donations from OnionTip.com"
echo "  - Optional: limit the amount of data transferred by your Tor relay (to avoid additional hosting costs)"
echo "    - Uncomment the lines beginning with '#AccountingMax' and '#AccountingStart'"
echo ""
echo "== Consider having /etc/apt/sources.list update over HTTPS and/or HTTPS+Tor"
echo "   see https://guardianproject.info/2014/10/16/reducing-metadata-leakage-from-software-updates/"
echo "   for more details"
echo ""
echo "== REBOOT THIS SERVER"
