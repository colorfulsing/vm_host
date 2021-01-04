# Description

Spirtual successor to this project -- [jlay/kernel-acspatch](https://copr.fedorainfracloud.org/coprs/jlay/kernel-acspatch/ "jlay kernel-acspatch Fedora copr repository page")

_What's new:_ Valve fsync patches are included in this variation

_What's the same:_ Fedora kernels with add-acs-overrides patch from Arch AUR:

[AUR linux-vfio](https://aur.archlinux.org/packages/linux-vfio/ "Arch AUR linux-vfio")

[add-acs-overrides.patch](https://aur.archlinux.org/cgit/aur.git/tree/add-acs-overrides.patch?h=linux-vfio "ACS patch")

[Local build automation -- Ansible, Fedora/mockbuild](https://git.jlay.dev/jlay/build-kernel "Ansible build-kernel playbook")

I will do my best to stay up to date with the latest Fedora (non-rawhide) kernels. Please see [builds](https://copr.fedorainfracloud.org/coprs/jlay/kernel-acsfsync/builds/ "Latest kernel builds") for the latest builds

Installation Instructions

**1** Enable the repository:

```bash
 dnf copr enable jlay/kernel-acsfsync
```

**2** Add `pci_acs_override=` to `GRUB_CMDLINE_LINUX` as necessary in `/etc/sysconfig/grub`

**`pci_acs_override` notes**

```bash
pcie_acs_override =
        [PCIE] Override missing PCIe ACS support for:
    downstream
        All downstream ports - full ACS capabilties
    multifunction
        All multifunction devices - multifunction ACS subset
    id:nnnn:nnnn
        Specfic device - full ACS capabilities
        Specified as vid:did (vendor/device ID) in hex
```

Here is my full `GRUB_CMDLINE_LINUX` in `/etc/sysconfig/grub` for reference:

```bash
GRUB_CMDLINE_LINUX="rd.lvm.lv=fedora/root rd.luks.uuid=luks-c6218459-1ccd-40b3-90da-da2b844a705e rd.lvm.lv=fedora/swap rhgb quiet iommu=1 amd_iommu=on pcie_acs_override=downstream,multifunction,id:1022:43b4 rd.driver.pre=vfio-pci default_hugepagesz=1G hugepagesz=1G hugepages=16 transparent_hugepage=never nordrand libata.noacpi=1"
```

I specify many (and possibly redundant) options for `pci_acs_override` (downstream,multifunction,id=1022:43b4) - not all of them may be necessary. Setting `pcie_acs_override=downstream` alone may be sufficient.

If using `id=`, you should provide the ID for the PCI-e bridge device connected to the PCI-e device you want in another IOMMU group. In my example above, I provide the ID for the PCI-e bridge connected to my Sound Blaster Z so that it is assigned a new IOMMU group and can be passed to a VM (VFIO):

```bash
[jlay@workstation ~]$ sudo lspci -nn | grep 1022:43b4
03:00.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] (rev 02)
[...]
03:07.0 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] 300 Series Chipset PCIe Port [1022:43b4] (rev 02)
```

The other CMDLINE settings I've provided are those I've set for general IOMMU/VFIO use - 16GB hugepages, enabling AMD IOMMU, and so on. They are not necessary for this patch (only `pcie_acs_override` for subdividing IOMMU groups further) but may prove useful for those on Ryzen systems (particularly `nordrand` to improve /dev/random performance).

**3** Install the updated kernel:

```bash
dnf update kernel --refresh
```