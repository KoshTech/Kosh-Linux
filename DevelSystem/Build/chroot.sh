#!/bin/bash

# Sample script to quick enter in chroot environment

cd Work
WORK=`pwd`
chroot "$WORK" /tools/bin/env -i HOME=/root TERM="$TERM" PS1='\u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin /tools/bin/bash --login +h
