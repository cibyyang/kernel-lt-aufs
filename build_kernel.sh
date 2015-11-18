#!/usr/bin/env bash

# rhel-aufs-kernel builder
# This script automates building out the latest kernel-ml package with AUFS support

# Get the kernel version to build
echo "What kernel version do you want to build? (major version only)"
read VERSION

# Get the architecture to build
echo "What architecture do you want to build for? (i686, i686-NONPAE, x86_64)"
read ARCH

# Get version of CentOS/RHEL to build for
echo "What version of CentOS/RHEL do you want to build for? (6 or 7)"
read EL_VERSION

# Thanks CentOS 7, you're a shining example of "worse is better"
if [ $EL_VERSION -eq 7 ]; then
  RPM_EL_VERSION="el7.centos"
else
  RPM_EL_VERSION="el6"
fi

# If our spec file is missing, exit
if [ ! -f kernel-ml-aufs/specs-el$EL_VERSION/kernel-ml-aufs-$VERSION.spec ]; then
  echo "Spec file not found for version $VERSION"
  exit 1
fi

# Get minor config version from spec file
FULL_VERSION=`cat kernel-ml-aufs/specs-el$EL_VERSION/kernel-ml-aufs-$VERSION.spec | grep "%define LKAver" | awk '{print $3}'`

# If we only have two parts to our version number, append ".0" to the end
VERSION_ARRAY=(`echo $FULL_VERSION | tr "." "\n"`)
if [ ${#VERSION_ARRAY[@]} -le 2 ]; then
  FULL_VERSION="$FULL_VERSION.0"
fi

# If our kernel config is missing, exit
if [ ! -f kernel-ml-aufs/configs-el$EL_VERSION/config-$FULL_VERSION-$ARCH ]; then
  echo "Config file not found for $FULL_VERSION-$ARCH"
  exit 1
fi

# See if we already have a build directory
if [ -d "build" ]; then
  echo "Build directory found! Removing..."
  rm -rf ./build
fi

# Create a build directory with all the stuff we need
echo "Creating build directory..."
mkdir -p build/logs
mkdir -p build/rpms
echo "Copying spec file and config file(s) to build directory..."
cp -a kernel-ml-aufs/specs-el$EL_VERSION/kernel-ml-aufs-$VERSION.spec build/
cp -a kernel-ml-aufs/configs-el$EL_VERSION/config-$FULL_VERSION-* build/
if [ $EL_VERSION -eq 7 ]; then
  cp -a kernel-ml-aufs/configs-el7/cpupower* build
fi

# From hereon out, everything we do will be in the temp directory
cd build

# Grab the source files for our kernel version
echo "Grabbing kernel source..."
spectool -g -C . kernel-ml-aufs-$VERSION.spec > logs/spectool.log 2>&1

# Clone the AUFS repo
if [[ $VERSION =~ ^4 ]]; then
  echo "Cloning AUFS 4.x..."
  git clone git://github.com/sfjro/aufs4-standalone.git -b aufs$VERSION aufs-standalone > logs/aufs-git.log 2>&1
  # Stupid workaround until 4.1 is tagged properly
  if [[ $? != 0 ]]; then
    git clone git://github.com/sfjro/aufs4-standalone.git -b aufs4.x-rcN aufs-standalone > logs/aufs-git.log 2>&1
  fi
else
  echo "Cloning AUFS 3.x..."
  git clone git://git.code.sf.net/p/aufs/aufs3-standalone -b aufs$VERSION aufs-standalone > logs/aufs-git.log 2>&1
fi

# Get the HEAD commit from the aufs tree
echo "Creating AUFS source tarball for packaging..."
pushd aufs-standalone
HEAD_COMMIT=`git rev-parse --short HEAD 2> /dev/null`
git archive $HEAD_COMMIT > ../aufs-standalone.tar
popd
rm -rf aufs-standalone

# Create our SRPM
echo "Creating source RPM..."
mock -r epel-$EL_VERSION-x86_64 --buildsrpm --spec kernel-ml-aufs-$VERSION.spec --sources . --resultdir rpms > logs/srpm_generation.log 2>&1

# If successful, create our binary RPMs
if [ $? -eq 0 ]; then
  echo "Source RPM created. Building binary RPMs..."
  mock -r epel-$EL_VERSION-x86_64 --rebuild --resultdir rpms rpms/kernel-ml-aufs-$FULL_VERSION-1.$RPM_EL_VERSION.src.rpm > logs/rpm_generation.log 2>&1
else
  echo "Could not create source RPM! Exiting!"
  exit 1
fi

if [ $? -eq 0 ]; then
  mkdir ~/RPMs
  echo "Binary RPMs created successfully! Moving to ~/RPMs..."
  mv rpms/*.rpm ~/RPMs
else
  echo "Binary RPM creation failed! See logs for details."
  exit 1
fi
