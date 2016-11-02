#!/bin/bash
<<__COPYRIGHT_AND_LICENSE__
    install-xe-guest-utilities.sh - automated installation of Citrix XenServer Tools (xe-guest-utilities) for Gentoo
    Copyright (C) 2011  Pandu E Poluan

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
    
    Contact information:
    
      * E-mail: <pandu@poluan.info>

      * Snail mail:
            Pandu E Poluan
            Jl. Bawang Merah 4 No. 9
            Komplek Kompas 3 - Ciputat
            Tangerang Selatan, Provinsi Banten
            INDONESIA 15411
            
__COPYRIGHT_AND_LICENSE__

# Description: Script to automate installation of Citrix XenServer xe-guest-utilities

DAEMONNAME=xe-daemon

INITSCRIPT=/etc/init.d/$DAEMONNAME
CONFSCRIPT=/etc/conf.d/$DAEMONNAME
APP=$(basename $0)


# Setting up colors & attributes *if* tput exists *and* display supports colors
if which tput &> /dev/null; then
  if (( $(tput colors) >=8 )); then
    c_c="$(tput setaf 6)"   #Cyan
    c_g="$(tput setaf 2)"   #Green
    c_r="$(tput setaf 1)"   #Red
    c_w="$(tput setaf 7)"   #White
    c_b="$(tput setaf 4)"   #Blue
    c_0="$(tput op)"        #Normal
    c__b="$(tput bold)"     #Begin bold
    c__0="$(tput sgr0)"     #End attributes

    c_cb="$c_c$c__b"         #Cyan Bold
    c_gb="$c_g$c__b"         #Green Bold
    c_rb="$c_r$c__b"         #Red Bold
    c_wb="$c_w$c__b"         #White BOld
    c_bb="$c_b$c__b"         #Blue Bold
    c_00="$c__0$c_0"         #Normal without attributes
  fi
fi

# Standardized help
# The coloring variables will not disturb the output even if display does not
# support colors, because they will be null ""
PrintHelp() {
  echo "
${c_wb}${APP}${c_00} - XenServer Guest Utilities Installer

SYNTAX:

    ${c_wb}${APP} ${c_c}PATH ARCH${c_00}

    ${c_cb}PATH${c_00} is either one of:
       1* Device where ${c_gb}xs-tools.iso${c_00} is loaded
       2* Path containing the ${c_rb}.rpm${c_00} files
       3* Path containing the ${c_bb}Linux${c_00} directory containing #2 above

    ${c_cb}ARCH${c_00} is either one of:
       ${c_cb}i386${c_00} if you need the 32-bit variant, or
       ${c_cb}x86_64${c_00} or ${c_cb}amd64${c_00} if you need the 64-bit variant.
       (The latter two are synonyms)
       
"
}


# First, check if help is requested. If so, emit help, and exit normally.
if [[ "-h" == "$1" || "--help" == "$1" ]] ; then
  PrintHelp
  exit 0
fi

# We need 2 parameters. If the 2nd parameter is null, print help, and exit abnormally
if [[ "" == "$2" ]] ; then
  PrintHelp
  exit 1
fi

# Limit allowable ARCH-es
case $2 in
  i386)
    ARCH=$2
    ;;
  x86_64|x86-64|amd64)
    ARCH=x86_64
    ;;
  *)
    PrintHelp
    exit 1
    ;;
esac

ERRCODE=0

ExitIfError() {
  if [[ $ERRCODE != 0 ]]; then
    exit $ERRCODE
  fi
}

ProgressReport() {
  printf "\n "
  if [[ $1 == 0 ]]; then
    printf "${c_gb}*${c_00} "
  else
    printf "${c_rb}*${c_00} "
    [[ $ERRCODE == 0 ]] && ERRCODE=$1
  fi
  printf "$2"
}

ErrorIfNotMerged() {
  if ! which $1 &> /dev/null; then
    ProgressReport 1 "Can't find ${c_wb}${1}${c_00}!"
    [[ "$2" ]] && ProgressReport 1 "Have you ${c_cb}emerge ${2}${c_00} yet?"
  fi
}

# Check if necessary tools are installed
ErrorIfNotMerged rpm2tar app-arch/rpm2targz
#ErrorIfNotMerged cpio     app-arch/cpio

# Let's process the source first
SRC=$1

if ! [[ -e $SRC ]]; then
  ProgressReport 1 "$SRC is not found!"
  ProgressReport 1 "Maybe you forgot to mount the ${c_cb}xs-tools.iso${c_00} image?"
fi

ExitIfError

# First, check if parameter is a block special file (in which case, we must mount)
if [[ -b $SRC ]]; then
  ProgressReport 0 "Mounting $SRC as /mnt"
  mount $SRC /mnt &> /dev/null
  SRCPATH=/mnt
else
  SRCPATH=$SRC
fi

# If the SRCPATH is not a directory, then abort
# (if $1 is a device, SRCPATH is the mounted path of the device)
if ! [[ -d $SRCPATH ]]; then
  ProgressReport 3 "${c_bb}$SRCPATH${c_00} is not found. Aborting!\n\n"
fi

ExitIfError

# Check that there are 2 .rpm files we need here
ProgressReport 0 "Searching for ${c_wb}$ARCH${c_00} .rpm files"
if (( $(find $SRCPATH -maxdepth 2 -name "xe-guest-utilities-*.$ARCH.rpm" | wc -l) < 2 )); then
    ProgressReport 3 "Can't find the needed ${c_rb}.rpm${c_00} files."
    ProgressReport 3 "Please check your parameters.\n\n"
    [[ -b $SRC ]] && umount $SRC
fi

ExitIfError

# Save our current directory, so we can exit the work directories
PREVDIR=$(pwd)

for f in $(find $SRCPATH -maxdepth 2 -name "xe-guest-utilities-*.$ARCH.rpm"); do
  TEMPDIR=$(mktemp -d)
  cd $TEMPDIR
  ProgressReport 0 "Extracting $(basename $f)"
  if ! rpm2tar -O $f | tar x &> /dev/null ; then
    ProgressReport 4 "Error while extracting ${c_rb}${f}${c_00} !!\n\n"
    ExitIfError
  fi
  if [[ $f =~ xenstore ]]; then
    DIRstore=$TEMPDIR
  else
    DIRutils=$TEMPDIR
  fi
done

### First, we process the utilities directory
ProgressReport 0 "Processing xe-guest-utilities"
procdirs=( /etc/udev/rules.d /usr )
for d in ${procdirs[@]}; do
  cp -r ${DIRutils}${d}/* $d
done

### Second, we process the xenstore directory
ProgressReport 0 "Processing xe-guest-utilities-xenstore"
cp -r ${DIRstore}/usr/* /usr
ProgressReport 0 "Remaking xenstore symbolic links"
for f in ${DIRstore}/usr/bin/xenstore-* ; do
  bf=$(basename $f)
  rm -f /usr/bin/$bf
  ln -s /usr/bin/xenstore /usr/bin/$bf
done

### Three, we create the proper, OpenRC-compatible initscript
ProgressReport 0 "Creating initscript"
cat - > $INITSCRIPT <<<'#!/sbin/runscript
# Copyright (c) 2011 Pandu E Poluan <pandu@poluan.info>
# Distributed under the terms of the GNU General Public License v2 or newer

description="xe-daemon enables the XenServer hypervisor to interrogate some status of the Gentoo DomU VM"
description_start="Starts the xe-daemon"
description_stop="Stops the xe-daemon"

depend() {
    need localmount
    after bootmisc
}

XE_LINUX_DISTRIBUTION=/usr/sbin/xe-linux-distribution
XE_LINUX_DISTRIBUTION_CACHE=/var/cache/xe-linux-distribution
XE_DAEMON=/usr/sbin/xe-daemon
XE_DAEMON_PIDFILE=/var/run/${SVCNAME}.pid

checkxen() {
    if [ ! -x "${XE_LINUX_DISTRIBUTION}" ] ; then
        eend 1 "${SVCNAME}: Could not find ${XE_LINUX_DISTRIBUTION}"
        return 1
    else
        return 0
    fi
}

checkdom0() {
    if [ -e /proc/xen/capabilities ] && grep -q control_d /proc/xen/capabilities ; then
      ewarn 1 "${SVCNAME}: Not necessary to run this in dom0"
      return 1
    else
      return 0
    fi
}

mountxenfs() {
    local XENFS_RSLT=0
    eindent
    if [ ! -e /proc/xen/xenbus ] ; then
        if [ ! -d /proc/xen ] ; then
            eerror "Could not find /proc/xen directory!"
            eerror "Need a post 2.6.29-rc1 kernel with CONFIG_XEN_COMPAT_XENFS=y and CONFIG_XENFS=y|m"
            XENFS_RSLT=1
        else
            # This is needed post 2.6.29-rc1 when /proc/xen support was pushed upstream as a xen filesystem
            if mount -t xenfs none /proc/xen ; then
                einfo "xenfs mounted on /proc/xen"
            else
                eerror "Failed mounting xenfs on /proc/xen!"
                XENFS_RSLT=1
            fi
        fi
    fi
    eoutdent
    return $XENFS_RSLT
}

start() {
    checkxen || return 1
    checkdom0 || return 1

    ebegin "${SVCNAME} starting"

    if mountxenfs ; then
      :
    else
      eend 1 "${SVCNAME} not started!"
      return 1
    fi

    eindent

      einfo "Detecting Linux distribution version"
      ${XE_LINUX_DISTRIBUTION} ${XE_LINUX_DISTRIBUTION_CACHE}

      einfo "Daemonizing"
      mkdir -p $(dirname ${XE_DAEMON_PIDFILE})

    eoutdent

    start-stop-daemon --start --exec "${XE_DAEMON}" --background \
        --pidfile "${XE_DAEMON_PIDFILE}" \
        -- -p ${XE_DAEMON_PIDFILE}

    eend $?
}

stop() {
    ebegin "Stopping ${SVCNAME}"
    start-stop-daemon --stop --exec "/usr/sbin/xe-daemon" --pidfile "${XE_DAEMON_PIDFILE}"
    eend $?
}

## End of xe-daemon initscript
'
chmod +x $INITSCRIPT



### We also will define some values for the relevant conf.d
cat - > $CONFSCRIPT <<< "\
# The parameters here sets how often xe-daemon poll for VM status

# How often the poll should happen
# Default: once every 60 seconds
# Active VMs that are nearing its limits should have a more frequent poll, but
# DO NOT go lower than 10
#XE_DAEMON_RATE=60

# Do memory poll every N cycles
# Default: once every 2 cycles
# Usually you want memory update to happen not more than once every 10 seconds,
# but not less than once every 2 minutes
#XE_MEMORY_UPDATE_DIVISOR=2
"



### Finally, patch /usr/sbin/xe-linux-distribution
ProgressReport 0 "Patching /usr/sbin/xe-linux-distribution"
cd /usr/sbin
patch <<< "\
--- xe-linux-distribution       2016-11-02 16:37:34.523484969 -0700
+++ xe-linux-distribution.gentoo  2016-11-02 16:40:08.434546532 -0700
@@ -285,6 +285,24 @@

 }

+identify_gentoo()
+{
+       gentoo_release="$1"
+       if [ ! -e "${gentoo_release}" ] ; then
+               return 1
+       fi
+       distro="gentoo"
+       eval $(cat ${gentoo_release} | awk '{ print "release=" $5 }' )
+       if [ -z "${release}" ] ; then
+               return 1
+       fi
+       eval $(echo $release | awk -F. -- '{ print "major=" $1 ; print "minor=" $2 }' )
+       if [ -z "${major}" -o -z "$minor" ] ; then
+               return 1
+       fi
+       write_to_output "${distro}" "${major}" "${minor}" "${distro}"
+}
+
 if [ $# -eq 1 ] ; then
     exec 1>"$1"
 fi
@@ -298,6 +316,7 @@
     identify_lsb    lsb_release         && exit 0
     identify_debian /etc/debian_version && exit 0
     identify_boot2docker /etc/boot2docker && exit 0
+    identify_gentoo /etc/gentoo-release && exit 0

     if [ $# -eq 1 ] ; then
        rm -f "$1"
" &> /dev/null

# Clean up
ProgressReport 0 "Cleaning up"
cd $PREVDIR
rm -rf $DIRutils $DIRstore

# Unmount if it was a device we're reading from
if [[ -b $SRC ]] ; then
  ProgressReport 0 "Unmounting $SRC"
  umount $SRC
fi

printf "\n
   Successfully installed xe-guest-utilities.
   You can start the xe-daemon by entering ${c_cb}/etc/init.d/xe-daemon start${c_00}

   If you want xe-daemon to automatically run on boot, enter the command:
   ${c_cb}rc-update add xe-daemon default${c_00}

   (Verify that xe-daemon indeed starts on boot by rebooting afterwards and
    check the daemon's status using ${c_cb}pgrep xe-daemon${c_00})
   
"

exit 0

## End of install-xe-guest-utilities.sh
