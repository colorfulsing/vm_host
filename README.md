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

You can set ``Export filesystem as readonly mount` option to make it read only.

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

## PCIe Pass-through

We will need several things for PCIe pass-through, one of those important things is to make sure that the PCIe device we want to pass-through is on it's own IOMMU group, or in case there are more PCIe devices on the same group, to be 100% sure we want to pass-through those devices too as you can only pass a IOMMU group as a whole.

Therefore, in case it is impossible to pass all devices on the IOMMU group because it would affect the host stability, or we simply are not happy with passing all devices on the IOMMU group, we can also use [ACS patch](https://aur.archlinux.org/cgit/aur.git/tree/add-acs-overrides.patch?h=linux-vfio "ACS patch") to split the specific devices we want into it's own IOMMU group. If this is the case, check the [Kernel with ACS patch](#kernel-with-acs-patch "Kernel with ACS patch") section.

To check the IOMMU groups, use the `check-iommu.sh` [script](https://github.com/colorfulsing/vm_host/blob/main/check-iommu.sh) (by Maagu Karuri) included on this repository, for example, let's say I will pass an NVIDIA graphics card:

```bash
$ ./check-iommu.sh | grep -B1 NVIDIA
IOMMU Group 8:
        01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117 [GeForce GTX 1650] [10de:1f82] (rev a1)
        01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:10fa] (rev a1)
```

TODO: Add step by step pass-through setup here

### Kernel with ACS patch

We need a kernel with ACS patch applied in order to isolate PCIe devices into it's own IOMMU group and be able to pass-through these devices into the VM, like a graphics card and a PCIe to USB extender to setup a gaming VM.

There are several ways to acquire a kernel with ACS patch, but these ones that I found useful are:

* Using [`jlay` Fedora kernel repository](#using-jlay-repository "Using jlay Fedora kernel repository")
* Recompile the kernel using docker(#recompile-the-kernel-using-docker "Recompile the kernel using docker")
* [Recompile the kernel manually](#recompile-the-kernel-manually "Recompile the kernel manually")

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

**NOTE1:** According to `dglb99`'s [post](https://forum.level1techs.com/t/trying-to-compile-acs-override-patch-and-got-stuck-fedora-33/163658/6), the script used the rebuild commands from [this](https://passthroughpo.st/agesa_fix_fedora/ "The Passthrough POST - HOWTO: Patch Fedora Kernel (feat. AGESA 0.0.7.2+ Fix)") guide on the original script.

**NOTE2:** `dglb99`'s original script also created a user called `mockbuild` which I would assume it was intended to be used along `mock` package to build the kernel but it wasn't used at the end and was left as a leftover on the script, so I removed it.

You can either open the script as text to execute each command individually for a more custom and controlled experience in case you want to do extra stuff, or you can simply execute it if you are looking for a one click installing everything on your system, like this:

```bash
# Replace <kernel_version> with the kernel version you want to compile.
# ./acs-override-script-fedora33.sh <kernel_version>
MY_KERNEL_VERSION="$(dnf list installed "kernel.x86_64" | grep -Eo '  [0-9][^ ]+' | grep -Eo '[^ ]+' | head -n 1)"
./acs-override-script-fedora33.sh "$MY_KERNEL_VERSION"
```
