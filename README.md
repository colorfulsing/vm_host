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

There are several ways to acquire a kernel with ACS patch, but the ones that I found useful are:

* `jlay` Fedora kernel repository
* Recompile the kernel manually

#### Using jlay repository

`jlay` have a really good and complete step by step guide on his Fedora copr repository page, which I totally recommend to [check it out](https://copr.fedorainfracloud.org/coprs/jlay/kernel-acsfsync/ "jlay's Fedora copr repository page"). But, I know some of us like headless stuff so [here](https://github.com/colorfulsing/vm_host/blob/main/jlay_copr_copy_paste.md "jlay's copy and paste step by step guide") is a copy and paste version stored on this git repository as of January 3, 2021.

You can also find his `build-kernel` ansible playbook on his repository [here](https://git.jlay.dev/jlay/build-kernel "jlay's build-kernel ansible playbook repository").

#### Recompile kernel manually

Check 's [script](https://raw.githubusercontent.com/colorfulsing/vm_host/main/acs-override-script-fedora33.sh "acs-override-script-fedora33.sh") included on this repository, it is a step by step script to compile Fedora's kernel (I added a variable to make the kernel package version dynamic).