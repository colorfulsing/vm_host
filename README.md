# Fedora 33 as host

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

## PCIe Passthrough

### Good stuff to read about

Here are some good guides and reading material to increase your knowledge and also to take a look over other ways to make the PCIe passthrough and some other stuff:

* General PCI Passthrough - [Arch linux's PCI passthrough via OVMF](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF "Arch linux's PCI passthrough via OVMF")
* Single GPU passthrough guide - [Karuri's vfio guide](https://gitlab.com/Karuri/vfio "Karuri's VFIO Single GPU Passthrough Configuration"). *(Totally recommend you to read this one)*
* Performance tunning - [bryansteiner's GPU passthrough tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial#----acs-override-patch-optional bryansteiner's GPU passthrough tutorial). *(Totally recommend you to read this one)*
* Fedora 32 with GPU passthrough - [marzukia's guide](https://marzukia.github.io/post/fedora-32-and-gpu-passthrough-vfio/ "marzukia's Fedora 32 and GPU Passthrough").
* Fedora 33 with GPU passthrough - [wendell's guide](https://forum.level1techs.com/t/fedora-33-ultimiate-vfio-guie-for-2020-2021-wip/163814 "wendell's Fedora 33: Ultimiate VFIO Guie for 2020/2021 [WIP]").
* LVM stuff - [Travis Johnson's LVM storage guide](https://bashtheshell.com/guide/configuring-lvm-storage-for-qemukvm-vms-using-virt-manager-on-centos-7/ "Travis Johnson's Configuring LVM Storage for QEMU/KVM VMs Using virt-manager on CentOS 7")

### My Fedora PCIe passthrough guide

We will need several things for PCIe passthrough, one of those important things is to make sure that the PCIe device we want to passthrough is on it's own IOMMU group, or in case there are more PCIe devices on the same group, to be 100% sure we want to passthrough those devices too as you can only pass a IOMMU group as a whole.

Therefore, in case it is impossible to pass all devices on the IOMMU group because it would affect the host stability, or we simply are not happy with passing all devices on the IOMMU group, we can also use [ACS patch](https://aur.archlinux.org/cgit/aur.git/tree/add-acs-overrides.patch?h=linux-vfio "ACS patch") to split the specific devices we want into it's own IOMMU group. If this is the case, check the [Kernel with ACS patch](#kernel-with-acs-patch "Kernel with ACS patch") section.

To check the IOMMU groups, use the `check-iommu.sh` [script](https://github.com/colorfulsing/vm_host/blob/main/check-iommu.sh) (by Maagu Karuri) included on this repository, for example, let's say I will pass an NVIDIA graphics card:

```bash
$ ./check-iommu.sh | grep -B1 NVIDIA
IOMMU Group 8:
        01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117 [GeForce GTX 1650] [10de:1f82] (rev a1)
        01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:10fa] (rev a1)
```

Now add the IOMMU grub parameters according to your CPU and system configuration:

* `intel_iommu=on` for **Intel CPUs** (VT-d) or `amd_iommu=on` for **AMD CPUs** (AMD-Vi).
* `iommu=pt` to prevent Linux from touching devices which cannot be passed through.
* `pcie_acs_override=downstream` only when using a kernel with ACS patch.
* `rd.driver.pre=vfio-pc` to force VFIO kernel module to load.

For example, when using `Fedora 33 + UEFI + AMD CPU + ACS override` then the grub parameters on my `/etc/default/grub` would be:

```bash
GRUB_CMDLINE_LINUX="rhgb quiet iommu=pt amd_iommu=on pcie_acs_override=downstream rd.driver.pre=vfio-pci"
```

/usr/lib/dracut/modules.d/module-setup.sh

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

```bash
mkdir /usr/lib/dracut/modules.d/20vfi
```

These values usually use a `0000` prefix, but you can check `/sys/bus/pci/devices` just to be sure this is the right prefix, otherwise, change it to whatever it is.

0000:01:00.0 0000:01:00.1

/usr/sbin/vfio-pci-override.sh

```sh
#!/bin/sh
PREREQS=""
DEVS="0000:01:00.0 0000:01:00.1"

for DEV in $DEVS; do
  echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
done

modprobe -i vfio-pc
```

```bash
ln -s /usr/sbin/vfio-pci-override.sh /usr/lib/dracut/modules.d/30vfio/vfio-pci-override.sh
```

/etc/dracut.conf.d/vfio.conf

```bash
dd_dracutmodules+=" vfio "
force_drivers+=" vfio vfio-pci vfio_virqfd vfio_iommu_type1 "
install_items="/usr/sbin/vfio-pci-override.sh /usr/bin/find /usr/bin/dirname"
```

```bash
dracut -fv
grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
```

```bash
sudo lsinitrd | grep vfio
```

TODO: Add step by step passthrough setup here

### Kernel with ACS patch

We need a kernel with ACS patch applied in order to isolate PCIe devices into it's own IOMMU group and be able to passthrough these devices into the VM, like a graphics card and a PCIe to USB extender to setup a gaming VM.

There are several ways to acquire a kernel with ACS patch, but these ones that I found useful are:

* Using [`jlay` Fedora kernel repository](#using-jlay-repository "Using jlay Fedora kernel repository")
* Recompile the kernel using docker(#recompile-the-kernel-using-docker "Recompile the kernel using docker")
* [Recompile the kernel manually](#recompile-the-kernel-manually "Recompile the kernel manually")

Once you have applied ACS patch, next step is to add `pcie_acs_override=downstream` along your other IOMMU kernel parameters to the grub default grub parameters.

Using `downstream` value on `pcie_acs_override` parameter should be more than enough for all your needs as it will split all components on different IOMMU groups, but you can also use other values as you need or mix any of them using `,` as separator. Check Arch linux's [PCI passthrough via OVMF](https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Bypassing_the_IOMMU_groups_%28ACS_override_patch%29 "Bypassing the IOMMU groups") for more information about it.

> **IMPORTANT:** Make sure you understand the [potential risks](https://vfio.blogspot.com/2014/08/iommu-groups-inside-and-out.html "IOMMU groups inside and out") of overriding the IOMMU groups before playing with this.

#### Using jlay Fedora kernel repository

`jlay` have a really good and complete step by step guide on his Fedora copr repository page, which I totally recommend to [check it out](https://copr.fedorainfracloud.org/coprs/jlay/kernel-acsfsync/ "jlay's Fedora copr repository page"). But, I know some of us like headless stuff so [here](https://github.com/colorfulsing/vm_host/blob/main/jlay_copr_copy_paste.md "jlay's copy and paste step by step guide") is a copy and paste version stored on this git repository as of January 3, 2021.

You can also find his `build-kernel` ansible playbook on his repository [here](https://git.jlay.dev/jlay/build-kernel "jlay's build-kernel ansible playbook repository").

#### Recompile the kernel using docker

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

#### Recompile the kernel manually

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
