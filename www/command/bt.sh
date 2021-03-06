#!/bin/bash
#
# moOde audio player (C) 2014 Tim Curtis
# http://moodeaudio.org
#
# Bluetooth controller management
# Copyright (C) 2017 Klaus Schulz
#
# This Program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# This Program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Written by Klaus Schulz
# Rev 1.0-beta1: 06-Oct-2017
# Rev 1.0-beta2: 19-Oct-2017
#        * some terminology changes and cleanup
#        * kill bluealsa-aplay (go offline!)to avoid playback during config
#        * show and kill active connections - "online"
#        * kill active connections before scanning 
#        * TODO: How to avoid double source connection?? 
#
# This script is designed to work with bluez and bluez-alsa
# It performs bluetooth controller initialization and provides management of bluetooth sources
# All related data files will reside under /var/lib/bluetooth
#
# 2017-11-26 TC moOde 4.0
# - REV 1.1
# - adapted for output to PHP/HTML 
# - simplified cmd api for BT config screen
# - added BTREMOVE(), BTDISCONNECT()
# - REV 1.2
# - revise html help for auto-initialize (happens in playerlib.php: startBt()
#

REV=1.2

# check environment
[[ $EUID -ne 0 ]] && { echo "*** You must be root to run the script! ***" ; exit 1 ; } ;
which expect >/dev/null || { echo "*** expect must be installed to run the script! ***" ; exit 1 ; } ;

# duration of scan in secs
SCANPERIOD=20

# initialze bluetooth controller
INIT() {
echo "*** Initializing Bluetooth controller"
echo "***"
rm -rf /var/lib/bluetooth/*
sleep 1
bluetoothctl -a << EOF
power on
discoverable on
pairable on
agent on
default-agent
EOF
echo "***"
echo "*** Controller initialized"
}
# scan for devices
SCAN() {
echo "*** Scanning for devices (${SCANPERIOD} secs)"
echo "***"
expect <(cat <<EOF
log_user 0
set timeout -1 
match_max 100000

spawn bluetoothctl
expect "*# " 
send -- "scan on\r"
expect -exact "scan on\r"
expect "*# " 

sleep $SCANPERIOD

send "scan off\r"
expect -exact "scan off\r"
expect "*# " 

send "quit\r"
expect eof
EOF
)
}
# trust scanned devices
TRUST() {
echo "*** Trusted devices"
unset btdev
mapfile -t btdev < <(echo -e "devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
for i in "${btdev[@]}" ; do
   echo "*** $i"
   y="$( echo $i | cut -d " " -f1)"
   echo -e "trust $y\nquit"  | bluetoothctl >/dev/null
   sleep 1
done   
echo "***"
}

# list discovered devices
LIST_DISCOVERED() {
unset btdev
mapfile -t btdev < <(echo -e "devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
#echo "*** ${#btdev[@]} Discovered device(s) "
echo "*** Discovered devices"
echo "***"
for i in "${btdev[@]}" ; do
   echo "*** $i"
   sleep 1
done
echo "***"
}
# list paired devices
LIST_PAIRED() {
unset btdev
mapfile -t btdev < <(echo -e "paired-devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
#echo "*** ${#btdev[@]} paired device(s) "
echo "*** Paired devices"
echo "***"
for i in "${btdev[@]}" ; do
   echo "*** $i"
   sleep 1
done
echo "***"
}
# list connected devices
LIST_CONNECTED() {
echo "*** Connected devices"
echo "***"
unset btdev
mapfile -t btdev < <(echo -e "paired-devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
for i in "${btdev[@]}" ; do
   MAC=$(echo "$i" | cut -f 1 -d " ")
   statconnected="$( echo -e "info $MAC\nquit"  | bluetoothctl | grep "Connected" | cut -f 2 -d " ")"
   if [ "$statconnected" == "yes" ] ; then echo "*** $i" ; fi
done
echo "***"
}

# remove all devices
REMOVE_ALL() {
echo "*** Removing all devices"
unset btdev
mapfile -t btdev < <(echo -e "devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
for i in "${btdev[@]}" ; do
   echo "*** $i"
   y="$( echo $i | cut -d " " -f1)"
   echo -e "remove $y\nquit"  | bluetoothctl >/dev/null
   sleep 1
done   
echo "*** All devices removed"
}
# disconnect all devices
DISCONNECT_ALL() {
echo "*** Disconnecting all devices"
unset btdev
mapfile -t btdev < <(echo -e "paired-devices\nquit"  | bluetoothctl | grep "^Device" |  while IFS= read -r line ; do echo "$line" |cut -d " " -f2- ; done )
for i in "${btdev[@]}" ; do
   MAC=$(echo "$i" | cut -f 1 -d " ")
   statconnected="$( echo -e "info $MAC\nquit"  | bluetoothctl | grep "Connected" | cut -f 2 -d " ")"
   if [ "$statconnected" == "yes" ] ; then echo -e "disconnect $MAC\nquit"  | bluetoothctl >/dev/null 2>&1 ; fi
done
# ensure no orphaned instances
killall bluealsa-aplay
echo "*** All devices disconnected"
}

# remove paired device
REMOVE_DEVICE() {
echo "*** Removing device $DEVICE"
echo -e "remove $DEVICE\nquit"  | bluetoothctl >/dev/null
sleep 1
echo "*** Device $DEVICE removed"
}
# disconenect device
DISCONNECT_DEVICE() {
echo "*** Disconnecting device $DEVICE"
echo -e "disconnect $DEVICE\nquit"  | bluetoothctl >/dev/null
sleep 1
echo "*** Device $DEVICE disconnected"
}

# print help to terminal
HELP_TERM() {
echo "*** BlueMoode version $REV"
echo "***"
echo "*** 1. INITIALIZE the controller."
echo "***    This only needs to be done once." 
echo "***"
echo "*** 2. SCAN for Bluetooth devices."
echo "***    First, put your device into discovery mode and verify that it"
echo "***    discovers Moode Bluetooth. You may have to turn Bluetooth off/on"
echo "***    on your device to accomplish this."  
echo "***"
echo "*** 3. PAIR your device to Moode Bluetooth. You may have to"
echo "***    initiate the connection (pairing) as soon as your device is"
echo "***    discovered and appears in the SCAN results. The pairing is stored"
echo "***    after a successful conection."
echo "***"
echo "*** Usage"
echo "*** -i initialize/reset controller"
echo "*** -s scan and trust devices"
echo "*** -l list discovered devices"
echo "*** -p list paired devices"
echo "*** -c list connected devices"
echo "*** -R remove all pairings"
echo "*** -r remove paired device <MAC addr>"
echo "*** -D disconnect all devices"
echo "*** -d disconnect device <MAC addr>"
echo "*** -h help"
}

# format help for html presentation
HELP_HTML() {
echo "BlueMoode version $REV"
echo
#echo "1) INITIALIZE controller."
#echo "This only needs to be done once!"
#echo
echo "1) SCAN for devices."
echo "First, put your device in discovery mode and verify that it discovers Moode Bluetooth. You may have to turn Bluetooth off/on on your device to accomplish this. The default duration of the scan is 20 seconds."
echo
echo "2) Connect your device to Moode Bluetooth. You may have to initiate the connection as soon as your device is discovered and appears in the SCAN results. After a successful connection the pairing is stored."
echo
echo "Other commands"
echo "- LIST paired" 
echo "- LIST connected" 
echo "- LIST discovered" 
echo "- REMOVE all pairings" 
echo "- DISCONNECT all devices" 
echo "- INITIALIZE controller" 
}

# main
	
	case $1 in 

	 -i) INIT
	     exit 0
	     ;;
	 -s) SCAN
         TRUST
         echo "*** Scan complete"
	     exit 0
	     ;;
	 -l) LIST_DISCOVERED
	     exit 0
	     ;;
	 -p) LIST_PAIRED
	     exit 0
	     ;;
	 -c) LIST_CONNECTED
	     exit 0
	     ;;
	 -R) REMOVE_ALL
	     sleep 3
	     LIST_PAIRED
	     exit 0
	     ;;
	 -r) DEVICE=$2
	 	 REMOVE_DEVICE
	     exit 0
	     ;;
	 -D) DISCONNECT_ALL
	     sleep 3
	     LIST_CONNECTED
	     exit 0
         ;;
	 -d) DEVICE=$2
	 	 DISCONNECT_DEVICE
	     exit 0
	     ;;
	 -h) HELP_TERM
	     exit 0
  	     ;;        
	 -H) HELP_HTML
	     exit 0
  	     ;;        
	 *)  HELP_TERM
	     exit 0
  	     ;;        
	 esac 

echo "***"
exit 0
