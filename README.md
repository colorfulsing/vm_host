# Fedora as host

The steps found on this guide have been tested on Fedora 33 and up to Fedora 39.

## Shared directories

### Host steps

Create a directory to share stuff within the virtual machines:

```bash
mkdir -p /vm_shared/my_vm_shared_dir
```

Now add SELinux file type label to allow `virt-manager` to access and mount it:


```bash
# Add virt_home_t context type to the shared directory permanently.
semanage fcontext -a -t virt_home_t "/vm_shared/my_vm_shared_dir(/*)?"

# Apply the new context policy to the shared directory.
restorecon -R /vm_shared/my_vm_shared_dir
```

Repeat to add any new shared directories.

Now add the new filesystem hardware into the virtual machine by clicking on `+ Add Hardware` button:

![](https://github.com/colorfulsing/vm_host/raw/main/images/shared_dir_filesystem.png)

You can set `Export filesystem as readonly mount` option to make it read only.

Here is the generated XML in case you want to add it manually to your VM:

```xml
<filesystem type="mount" accessmode="mapped">
  <source dir="/vm_shared/my_vm_shared_dir"/>
  <target dir="/vm_shared/my_vm_shared_dir"/>
  <alias name="fs0"/>
</filesystem>
```

### Guest steps

Create the target directory into the guest VM, for simplicity, we will use the same `/vm_shared/my_vm_shared_dir` directory:

```bash
mkdir -p /vm_shared/my_vm_shared_dir
```

Temporarily mount the shared directory on the guest VM:

```bash
# Replace `<vm_target>` with whatever you set on the VM's hardware `Target path`.
# Replace `<guest_target>` with whatever guest directory you want to mount it.
# mount -t 9p -o trans=virtio,version=9p2000.L <vm_target> <guest_target>

sudo mount -t 9p -o trans=virtio,version=9p2000.L /vm_shared/my_vm_shared_dir /vm_shared/my_vm_shared_dir
```

You can also modify `/etc/fstab` file to make it permanently, to do this, just add the following:

```bash
# Set `fsck_order` to 0 to disable it (recommended).
# <vm_target> <guest_target> <type> <options> <dump_frequency> <fsck_order>
/vm_shared/my_vm_shared_dir /vm_shared/my_vm_shared_dir 9p trans=virtio,version=9p2000.L 0 0
```

And then apply all mounts described on `/etc/fstab` like this:

```bash
sudo mount -a
```

And done, now you can share your files between your Host and Guest VM.

## PCI Passthrough

### Good stuff to read about

Here are some good guides and reading material to increase your knowledge and also to take a look over other ways to make the PCI passthrough and some other stuff:

* General PCI Passthrough - [Arch linux's PCI passthrough via OVMF](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF "Arch linux's PCI passthrough via OVMF")
* Single GPU passthrough guide - [Karuri's vfio guide](https://gitlab.com/Karuri/vfio "Karuri's VFIO Single GPU Passthrough Configuration"). *(Totally recommend you to read this one)*
* Performance tunning - [bryansteiner's GPU passthrough tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial#----acs-override-patch-optional bryansteiner's GPU passthrough tutorial). *(Totally recommend you to read this one)*
* Fedora 32 with GPU passthrough - [marzukia's guide](https://marzukia.github.io/post/fedora-32-and-gpu-passthrough-vfio/ "marzukia's Fedora 32 and GPU Passthrough").
* Fedora 33 with GPU passthrough - [wendell's guide](https://forum.level1techs.com/t/fedora-33-ultimiate-vfio-guie-for-2020-2021-wip/163814 "wendell's Fedora 33: Ultimiate VFIO Guie for 2020/2021 [WIP]").
* LVM stuff - [Travis Johnson's LVM storage guide](https://bashtheshell.com/guide/configuring-lvm-storage-for-qemukvm-vms-using-virt-manager-on-centos-7/ "Travis Johnson's Configuring LVM Storage for QEMU/KVM VMs Using virt-manager on CentOS 7")

### GPU PCI passthrough guide

We will need several things for PCI passthrough, one of those important things is to make sure that the PCI device we want to passthrough is on it's own IOMMU group, or in case there are more PCI devices on the same group, to be 100% sure we want to passthrough those devices too as you can only pass a IOMMU group as a whole.

Therefore, in case it is impossible to pass all devices on the IOMMU group because it would affect the host stability, or we simply are not happy with passing all devices on the IOMMU group, we can also use [ACS patch](https://aur.archlinux.org/cgit/aur.git/tree/add-acs-overrides.patch?h=linux-vfio "ACS patch") to split the specific devices we want into it's own IOMMU group. If this is the case, check the [Kernel with ACS patch](#kernel-with-acs-patch "Kernel with ACS patch") section.

To check the IOMMU groups, use the `check-iommu.sh` [script](https://github.com/colorfulsing/vm_host/blob/main/check-iommu.sh) (by Maagu Karuri) included on this repository, for example, let's say I will pass an NVIDIA graphics card:

```bash
$ ./check-iommu.sh | grep -B1 NVIDIA
IOMMU Group 8:
        01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117 [GeForce GTX 1650] [10de:1f82] (rev a1)
        01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:10fa] (rev a1)
```

Take note over both vendor and product IDs as we will need to override those on the grub params to make it work, for this example, the values are `10de:1f82` for the video device and `10de:10fa` for the audio device, as well as the device IDs that we will use to override the driver a bit later on the guide, those wold be `01:00.0` for video device and `01:00.1` for audio device.

>**IMPORTANT**: IOMMU groups rules applies. You have to pass all devices on the same IOMMU group.

Now add the IOMMU grub parameters according to your CPU and system configuration:

* `intel_iommu=on` for **Intel CPUs** (VT-d) or `amd_iommu=on` for **AMD CPUs** (AMD-Vi).
* `iommu=pt` to prevent Linux from touching devices which cannot be passed through.
* `pcie_acs_override=downstream` only when using a kernel with ACS patch.
* `rd.driver.pre=vfio-pc` to force VFIO kernel module to load.
* `vfio-pci.ids` PCI devices' vendor and product IDs to passhtrough.

For example, when using `Fedora 33 + UEFI + AMD CPU + ACS override` and the NVIDIA GPU vendor and product IDs from before, then the grub parameters to add on `/etc/default/grub` (UEFI grub file location, check `/etc/sysconfig/grub` instead if using BIOS) would be:

```bash
GRUB_CMDLINE_LINUX="rhgb quiet iommu=pt amd_iommu=on pcie_acs_override=downstream rd.driver.pre=vfio-pci vfio-pci.ids=10de:1f82,10de:10fa"
```

Next, create `/usr/lib/dracut/modules.d/module-setup.sh` file to provide dracut with the module setup functions:

```bash
#!/usr/bin/bash
check() {
  return 0
}
depends() {
  return 0
}
install() {
  declare moddir=${moddir}
  inst_hook pre-udev 00 "$moddir/vfio-pci-override.sh"
}
```

Make sure that `/usr/lib/dracut/modules.d/module-setup.sh` is executable:

```bash
chmod +x /usr/lib/dracut/modules.d/module-setup.sh
```

Now let's create `/usr/sbin/vfio-pci-override.sh` to override the PCI devices's driver we want to passthrough. Remember that you should pass the whole IOMMU group not just the devices you want.

To do this, we need to use the device IDs we extracted before using `check-iommu.sh` script (`01:00.0` for video device and `01:00.1` for audio device) and add it to `DEVS` variable at `/usr/sbin/vfio-pci-override.sh` script and add `0000` as prefix:

```sh
#!/bin/sh
PREREQS=""
DEVS="0000:01:00.0 0000:01:00.1"

if [ ! -z "$(ls -A /sys/class/iommu)" ]; then
    for DEV in $DEVS; do
        echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    done
fi

modprobe -i vfio-pci
```

>**Note:** Notice that these values usually use `0000` as prefix, but you can check `/sys/bus/pci/devices` just to be sure this is the right prefix, otherwise, change it to whatever it is.

Make sure that `/usr/sbin/vfio-pci-override.sh` is executable:

```bash
chmod +x /usr/sbin/vfio-pci-override.sh
```

Next, add a symbolic link to provide `vfio-pci-override.sh` as a dracut module within the correct order, as we need to make sure that it executes before any other driver does. To do this, we add `20` to the directory name to ensure the correct execution order:

```bash
mkdir /usr/lib/dracut/modules.d/20vfio
ln -s /usr/sbin/vfio-pci-override.sh /usr/lib/dracut/modules.d/30vfio/vfio-pci-override.sh
```

Next step is to enable `vfio-pci` driver, module and it's related grub options by creating a new module configuration file on `/etc/modprobe.d/vfio.conf`:

```bash
install vfio-pci /usr/sbin/vfio-pci-override.sh; /sbin/modprobe --ignore-install vfio-pci

options vfio-pci disable_vga=1
```

We also need to ensure that dracut loads all `vfio` related drivers and modules, along our `vfio-pci-override.sh` to ensure it will override the driver settings of the PCI devices we want to passthrough. To do this, let's create `/etc/dracut.conf.d/vfio.conf` file, however, this file contents will change depending on the kernel version you are using because of the built-in modules:

Using kernel **< v6.0**:

```bash
dd_dracutmodules+=" vfio "
force_drivers+=" vfio vfio-pci vfio_virqfd vfio_iommu_type1 "
install_items="/usr/sbin/vfio-pci-override.sh /usr/bin/find /usr/bin/dirname"
```

Using kernel **>= v6.0**:

```bash
dd_dracutmodules+=" vfio "
force_drivers+=" vfio vfio-pci vfio_iommu_type1 "
install_items="/usr/sbin/vfio-pci-override.sh /usr/bin/find /usr/bin/dirname"
```

And finally, we rebuild both `initramfs` and `grub` configuration file:

```bash
dracut -fv
grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
```

Now you just need to reboot and check that everthing is okay.

Check for `initramfs` to include `vfio` module and drivers:

```bash
$ lsinitrd | grep vfio
-rw-r--r--   1 root     root          122 Oct 23 09:30 etc/modprobe.d/vfio.conf
drwxr-xr-x   3 root     root            0 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio
drwxr-xr-x   2 root     root            0 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio/pci
-rw-r--r--   1 root     root        29632 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio/pci/vfio-pci.ko.xz
-rw-r--r--   1 root     root        15704 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio/vfio_iommu_type1.ko.xz
-rw-r--r--   1 root     root        12880 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio/vfio.ko.xz
-rw-r--r--   1 root     root         3216 Oct 23 09:30 usr/lib/modules/5.9.16-200.fc33.x86_64/kernel/drivers/vfio/vfio_virqfd.ko.xz
-rwxr-xr-x   1 root     root          241 Oct 23 09:30 usr/sbin/vfio-pci-override.sh
```

Check for devices' driver override and `vfio-pci` driver usage (it should list all the PCI devices you passthrough):

```bash
$ lspci -nnk | grep -B2 vfio
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117 [GeForce GTX 1650] [10de:1f82] (rev a1)
        Subsystem: ZOTAC International (MCO) Ltd. Device [19da:1546]
        Kernel driver in use: vfio-pci
--
01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:10fa] (rev a1)
        Subsystem: ZOTAC International (MCO) Ltd. Device [19da:1546]
        Kernel driver in use: vfio-pci
```

## USB PCI Passthrough guide

The vfio-pci driver override method used on the [GPU PCI Passthrough guide](#gpu-pci-passthrough-guide "GPU PCI Passthrough guide") section is usually ineffective when comes to USB PCI devices as it usually requires kernel drivers compiled within the kernel (like `xhci_hcd`) instead of modules that can be enable/disable. This of course, is troublesome as it prevents our override scripts and configuration from working.

Thankfully, we can bypass this limitation by using `driverctl`and setting the driver override on the fly which unbind the USB PCI device's driver and bind it back using `vfio-pci` or any other we would like, for example, let's say we want to passthrough this USB PCIe device:

```bash
$ ./check-iommu.sh | grep -B1 VIA
IOMMU Group 16:
        05:00.0 USB controller [0c03]: VIA Technologies, Inc. VL805 USB 3.0 Host Controller [1106:3483] (rev 01)
````

Take note of the device ID, we will need it to use `driverctl`, on this example, the ID is `05:00.0`.

>**IMPORTANT**: IOMMU groups rules applies on this kind of passthrough too. You have to pass all devices on the same IOMMU group.

Now we install `driverctl` CLI utility:

```bash
dnf install driverctl
```

And finallly set all devices on the same IOMMU group to use `vfio-pci` driver like this:

```bash
$ driverctl -v set-override 0000:05:00.0 vfio-pci
driverctl: setting driver override for 0000:05:00.0: vfio-pci
driverctl: loading driver vfio-pci
driverctl: unbinding previous driver xhci_hcd
driverctl: reprobing driver for 0000:05:00.0
driverctl: saving driver override for 0000:05:00.0
```

Once this is done, the overrides will be applied inmediatly and also persists on reboot. All that is left is to verify that the override worked as expected:

```bash
$ lspci -nnk | grep -A2 '05:00.0'
05:00.0 USB controller [0c03]: VIA Technologies, Inc. VL805 USB 3.0 Host Controller [1106:3483] (rev 01)
        Subsystem: VIA Technologies, Inc. VL805 USB 3.0 Host Controller [1106:3483]
        Kernel driver in use: vfio-pci
```

## Kernel with ACS patch

We need a kernel with ACS patch applied in order to isolate PCI devices into it's own IOMMU group and be able to passthrough these devices into the VM, like a graphics card and a PCI to USB extender to setup a gaming VM.

There are several ways to acquire a kernel with ACS patch, but these ones that I found useful are:

* Using [`jlay` Fedora kernel repository](#using-jlay-repository "Using jlay Fedora kernel repository")
* Recompile the kernel using docker(#recompile-the-kernel-using-docker "Recompile the kernel using docker")
* [Recompile the kernel manually](#recompile-the-kernel-manually "Recompile the kernel manually")

Once you have applied ACS patch, next step is to add `pcie_acs_override=downstream` along your other IOMMU kernel parameters to the grub default grub parameters.

Using `downstream` value on `pcie_acs_override` parameter should be more than enough for all your needs as it will split all components on different IOMMU groups, but you can also use other values as you need or mix any of them using `,` as separator. Check Arch linux's [PCI passthrough via OVMF](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Bypassing_the_IOMMU_groups_%28ACS_override_patch%29 "Bypassing the IOMMU groups") for more information about it.

> **IMPORTANT:** Make sure you understand the [potential risks](https://vfio.blogspot.com/2014/08/iommu-groups-inside-and-out.html "IOMMU groups inside and out") of overriding the IOMMU groups before playing with this.

### Using jlay Fedora kernel repository

`jlay` have a really good and complete step by step guide on his Fedora copr repository page, which I totally recommend to [check it out](https://copr.fedorainfracloud.org/coprs/jlay/kernel-acsfsync/ "jlay's Fedora copr repository page"). But, I know some of us like headless stuff so [here](https://github.com/colorfulsing/vm_host/blob/main/jlay_copr_copy_paste.md "jlay's copy and paste step by step guide") is a copy and paste version stored on this git repository as of January 3, 2021.

You can also find his `build-kernel` ansible playbook on his repository [here](https://git.jlay.dev/jlay/build-kernel "jlay's build-kernel ansible playbook repository").

### Recompile the kernel using docker

Easiest way to recompile kernel and build fresh Fedora RPM packages.

**Fedora 32:** I recommend you to use [`stefanleh`'s acs_fedora docker image](https://hub.docker.com/r/stefanlehmann/acs_fedora "stefanlehmann/acs_fedora"). You can find his docker image github repository [here](https://github.com/stefanleh/fedora_acs_kernel_build "stefanleh's fedora_acs_kernel_build github repository") and you can use it like this:

```bash
# Replace <local_dir> with the local directory where you want the packages to be created
# Replace <kernel_version> with the kernel version you want to recompile
# docker run -it -v <local_dir>:/rpms stefanlehmann/acs_fedora <kernel_version>
MY_KERNEL_VERSION="$(dnf list installed "kernel.x86_64" | grep -Eo '  [0-9][^ ]+' | grep -Eo '[^ ]+' | head -n 1)"
docker run --rm -it -v /mnt:/rpms stefanlehmann/acs_fedora "${MY_KERNEL_VERSION}"
```

**Fedora 33:** I recommend you to use my [acs_fedora_33 docker image](https://hub.docker.com/r/colorfulsing/acs_fedora_33 "colorfulsing/acs_fedora_33"). You can find my docker image github repository [here](https://github.com/colorfulsing/build_fedora_kernel "colorfulsing's build_fedora_kernel github repository") and you can use it like this:

```bash
# Replace <local_dir> with the local directory where you want the packages to be created
# Replace <kernel_version> with the kernel version you want to recompile
# docker run -it -v <local_dir>:/rpms colorfulsing/acs_fedora_33 <kernel_version>
MY_KERNEL_VERSION="$(dnf list installed "kernel.x86_64" | grep -Eo '  [0-9][^ ]+' | grep -Eo '[^ ]+' | head -n 1)"
docker run --rm -it -v /mnt:/rpms colorfulsing/acs_fedora_33 "${MY_KERNEL_VERSION}"
```

### Recompile the kernel manually

Check this [script](https://github.com/colorfulsing/build_fedora_kernel/blob/main/acs-override-script-fedora33.sh "acs-override-script-fedora33.sh") created by [`dglb99`](https://forum.level1techs.com/u/dglb99 "dglb99") and modified by me. It is a step by step script to compile Fedora's kernel with ACS patch that has been modified by me to provide the following:

* Detect your currently installed kernel version (check the `MY_KERNEL_VERSION` variable on the script).
* Add AGESA patch.
* Error checks.
* Docker build mode.

> **NOTE<sup>1</sup>:** According to `dglb99`'s [post](https://forum.level1techs.com/t/trying-to-compile-acs-override-patch-and-got-stuck-fedora-33/163658/6), the script was created using the rebuild commands from [this](https://passthroughpo.st/agesa_fix_fedora/ "The Passthrough POST - HOWTO: Patch Fedora Kernel (feat. AGESA 0.0.7.2+ Fix)") guide on the original script.

> **NOTE<sup>2</sup>:** `dglb99`'s original script also created a user called `mockbuild` which I would assume it was intended to be used along `mock` package to build the kernel but it wasn't used at the end and was left as a leftover on the script, so I removed it.

You can either open the script as text to execute each command individually for a more custom and controlled experience in case you want to do extra stuff, or you can simply execute it if you are looking for a one click installing everything on your system, like this:

```bash
# Replace <kernel_version> with the kernel version you want to compile.
# ./acs-override-script-fedora33.sh <kernel_version>
MY_KERNEL_VERSION="$(dnf list installed "kernel.x86_64" | grep -Eo '  [0-9][^ ]+' | grep -Eo '[^ ]+' | head -n 1)"
./acs-override-script-fedora33.sh "$MY_KERNEL_VERSION"
```

## How to create a network bridge

First check what is the current hardware interface it is usually called something like enp0s0

```bash
$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq master br0 state UP group default qlen 1000
    link/ether b4:2e:99:f1:ed:a0 brd ff:ff:ff:ff:ff:ff
```

On this example the hardware interface is called `enp5s0`.

Now create new host connection interface, it will be used as master of the bridge (use the bridge)

```bash
$ nmcli conn add type bridge con-name br0 ifname br0
```

Then create bidge using hardware interface `enp5s0` (remember that it may change on each computer)

```bash
$ nmcli conn add type ethernet slave-type bridge con-name bridge-br0 ifname enp5s0 master br0
```

Bring new host connection internface up

```bash
$ nmcli conn up br0
```

Shutdown old host connection interface so the bridge can use the hardware interface, for this example we will assume the name of the interface is `wired`, but keep in mind that yours might be named `Wired connection 0` or something similar

```bash
$ nmcli conn down "wired"
```

And finally restart the computer to apply the changes

```bash
$ shutdown -r now
```

### Configure bridge's DNS to cloudflare

Setup cloudflare's IPv4 and IPv6 DNS on the new host connecition interface

```bash
$ nmcli connection modify br0 ipv4.dns "1.1.1.1,1.0.0.1"
$ nmcli connection modify br0 ipv4.ignore-auto-dns "yes"
$ nmcli connection modify br0 ipv6.dns "2606:4700:4700::1111,2606:4700:4700::1001"
$ nmcli connection modify br0 ipv6.ignore-auto-dns "yes"
```

Now check that the configuration is okay

```bash
$ nmcli connection show br0
```

Then, flush the DNS cache and restart the DNS resolver service

```bash
$ sudo resolvectl flush-caches
$ sudo systemctl restart systemd-resolved
```

And finally restart the computer to apply the changes

```bash
$ shutdown -r now
```

### Remove the bridge connection

If for some reason your bridge stop working or you simple want to remove it, then first you need to remove the `slave-type` bridge we added before, it's name should be `bridge-br0`

```bash
$ nmcli conn delete bridge-br0
```

Next remove the bridge itself

```bash
$ nmcli conn delete br0
```

Then bring the old host connectio interface up, just as before, we will assume the name of the interface is `wired` for this example, but keep in mind that yours might be named `Wired connection 0` or something similar

```bash
$ nmcli conn up "wired"
```

Finally, restart your computer for the changes to take effect

```bash
$ shutdown -r now
```

## Performance tunning

In order to get the best performance on our VMs, we need to change a few settings to provide a big boost to it's performance in general. I will describe some of them that are quite useful when comes to a dedicated hypervisor PC.

Alternatively, if you plan on have a kind of hybrid workstation + gaming VM, then you can check on [bryansteiner's GPU passthrough tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial#----acs-override-patch-optional bryansteiner's GPU passthrough tutorial) for several additional configurations to improve your gaming VM performance with dynamic resource allocation so you can have the best of both world on your PC.

### CPU Governor

The default governor is either `schedutil` (>= 5.10 kernel) or `powersave` (< 5.10 kernel), but these governors are not a good fit for a VM since the VM itself will try to handle the CPU load. To fix this, we can either set it as `performance` governor which will set all CPU to the maximum clock, or `ondemand` for a more dynamic approach with kind of the same results but with a less impact on CPU. I will use `ondemand` on this guide as it fits best my own preferences.

There are several ways to set the default CPU governor from we can choose from:

* GRUB option
* `udev` rule
* Userspace app like cpupower

I recommend you to use `udev` rule to avoid race conditions and also to be able to easy change it or rollback in case it doesn't fit your needs.

Create a `udev` file at `/etc/udev/rules.d/50-scaling-governor.rules` to change the CPU governor to `ondemand`

```
SUBSYSTEM=="module", ACTION=="add", KERNEL=="acpi_cpufreq", RUN+="/bin/sh -c 'echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor'"
```

Finally, reboot to apply the changes.

### Memory Hugepages

Hugepages are quite useful to provide our VMs with lots of memory while easing it's allocation overhead, which improves our VMs performance.

You can either allocate it during boot time or on runtime, both having their upsides and downsides. We will use `huge pages on boot time` on this tutorial as this is a dedicated host.

Here are the downsides of each just so you know:

* Allocating memory huge pages on boot time is really easy, but it has the downside or reserving the RAM for the VMs leaving this ram unvailable for the host.
* Allocating memory huge pages on runtime is tricky but with the advantage that the host will enjoy all the RAM while the VM is not in use.

#### Create Hugepages mount point

To allocate memory huge pages on boot time, we first need to check if hugepages is already mounted

```bash
$ mount | grep hugetlbfs
hugetlbfs on /dev/hugepages type hugetlbfs (rw,relatime,seclabel,pagesize=2M)
```

if you got a mount rule, the you can skip this section.

Else, if **you didn't got any mount rule with the previous command**, then you need to first create the `/dev/hugepages` directory

```bash
$ mkdir /dev/hugepages
```

Next, add the following rule to your `/etc/fstab` file and assign it to the `kvm` user like this

```
hugetlbfs /dev/hugepages hugetlbfs mode=01770,gid=kvm 0 0
```

> **NOTE<sup>1</sup>:** Notice the `gid=kvm` which is our `kvm` group, you can change it to it's numeric `gid` but I would recommend you to use the `kvm` as it may change depending on your distro.

> **NOTE<sup>2</sup>:** `/dev/hugepages` might change depending on your distro, or don't even exists if hugepages is not implemented. You can create `/dev/hugepages` if it doesn't exists.

And finally, add the rule to your `qemu` configuration file, usually located at `/etc/libvirt/qemu.conf`

```
hugetlbfs_mount = "/dev/hugepages"
```

#### Allocating Hugepages on boot

Next we need to calculate how many hugepages we will need, to do this, we need first to find out what is our hugepage size by checking `/proc/meminfo` utility

```bash
$ grep Hugepagesize /proc/meminfo
Hugepagesize:       2048 kB
```

On my particular case, it is 2MB size and I need to allocate a total of 24576MB (or 24GB) for my PC so I will use that for this example, but you can use whatever memory size you want.

So, by doing the math `24576 / 2 = 12288`, I will need `12288` hugepages total, however, it is usually a good idea to add a few more just in case the OS needs it, so let's round it up to `12350`.

Now, before we enable this by default, it is a good idea to test it just to make sure everything works without issues, to do this, let's apply it on runtime

```bash
echo 12350 > /proc/sys/vm/nr_hugepages
```

And now let's check if the quantity is correct

```bash
$ grep HugePages_Total /proc/meminfo
HugePages_Total:       12350
```

In case the number displayed by the previous command is smaller, try to close some applications as it the OS will try to allocate as much as it can within the free memory.

Now that we know it is safe and it was allocated correctly, next step is to try your VM and check on the 

```bash
$ grep HugePages /proc/meminfo
HugePages_Total:   12288
HugePages_Free:       62
HugePages_Rsvd:        0
HugePages_Surp:        0
```

> **NOTE:** You might need to specify the memory mount path param (`-mem-path`) when starting your VM for it to use it in case it is not your libvirt standard setting.

Finally, now that we had make sure that our hugepages settings works, let's add the permanent setting by creating a `/etc/sysctl.d/40-hugepage.conf` file with the following contents

```
vm.nr_hugepages = 12350
```

## VM Suspend and Wake up

List VM states:

```bash
virsh -c qemu:///system list --all
```

Wake up a `pmsuspended` VM (replace `[vm_name]` with your VM name):

```bash
virsh -c qemu:///system dompmwakeup [vm_name]
```

## Troubleshooting

### Fix: Spice VDAgent not working on Wayland

I found that when using `spice display` it `virt-viewer` stopped resizing along some other stuff. The problem was that the `spice-vdagent` wasn't running (not to be confused with `spice-vdagentd`), so we just need to create a `systemctl` user service at `~/.local/share/systemd/user/spice-vdagent.service`:

```ini
[Unit]
Description=Agent daemon for Spice guests

[Service]
Type=simple
ExecStart=/usr/bin/spice-vdagent -x
Restart=on-failure

[Install]
WantedBy=default.target
```

And then enable it using `systemctl` in `user` mode like this (remember that these doesn't use `sudo` since it has to be executed as your user!):

```bash
systemctl --user daemon-reload
systemctl --user enable spice-vdagent
systemctl --user start spice-vdagent
```
