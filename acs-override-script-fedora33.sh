#!/bin/bash

# Created by dglb99, I just added the kernel package version as a variable
# https://forum.level1techs.com/t/trying-to-compile-acs-override-patch-and-got-stuck-fedora-33/163658/6

#Check for updates
sudo dnf check-update
sudo dnf upgrade

#install ‘mockbuild’ user
sudo yum install mock
sudo useradd -s /sbin/nologin mockbuild

#get kernel version
MY_KERNEL_VERSION="$(dnf list installed "kernel.x86_64" | grep -Eo '  [0-9][^ ]+' | grep -Eo '[^ ]+')"

#1 Add RPM Fusion
sudo dnf install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-(rpm -E %fedora).noarch.rpm

#2 Add dependencies to build your own kernel
sudo dnf install fedpkg fedora-packager rpmdevtools ncurses-devel pesign

#3 Set home build directory
rpmdev-setuptree

#4 Install the kernel source and finish installing dependencies
cd ~/rpmbuild/SOURCES
koji download-build --arch=src "kernel-${MY_KERNEL_VERSION}"
rpm -Uvh "kernel-${MY_KERNEL_VERSION}.src.rpm"
cd ~/rpmbuild/SPECS/
sudo dnf builddep kernel.spec

#5 Add the ACS patch (link) as ~/rpmbuild/SOURCES/add-acs-override.patch
mkdir ~/acs-patch-files
cd ~/acs-patch-files
git clone https://aur.archlinux.org/linux-vfio.git
cp ~/acs-patch-files/linux-vfio/add-acs-overrides.patch ~/rpmbuild/SOURCES

#6 Edit ~/rpmbuild/SPECS/kernel.spec to set the build ID and add the patch. Since each release of the spec file could change, it’s not much help giving line numbers, but both of these should be near the top of the file.
cd ~/rpmbuild/SPECS
ls
sed -i '31 i # Set buildid' ./kernel.spec
sed -i '32 i %define buildid .acs' ./kernel.spec
sed -i '33 i # ACS overrides patch' ./kernel.spec
sed -i '34 i Patch1000: add-acs-overrides.patch' ./kernel.spec
#This is the part of my script that inserts the build ID into the kernel.spec file

#7 Compile the kernel! This can take a while.
cd ~/rpmbuilds/SPECS
ls
rpmbuild -bb --without debug --target=x86_64 kernel.spec

#8 install the kernel
cd ~/rpmbuild/RPMS/x86_64
sudo dnf update *.rpm

#9 Update Grub Config
sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg

#10 update and reboot
sudo dnf clean all
sudo dnf update -y
sudo reboot
