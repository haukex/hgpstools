#!/bin/bash
set -e
# simple script to fetch lease information for all known interfaces
for IF in $(ifconfig -a | perl -lne 'print $1 if /^(\S+)\s/')
do
	echo "[$IF]"
	dhcpcd -U $IF
done
