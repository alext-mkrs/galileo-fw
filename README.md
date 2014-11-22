galileo-fw
==========

Scripts for automated building of Galieo board firmware.

**Given that there's no longer that much of a demand for this automated solution seen in the Galileo Community and official images are now not lagging behind the BSP updates as it was at the beginning - I don't see a need to update this project any more. Feel free to fork it for your needs or contact me by submitting a bug/feature request here or in the Galileo Community forum at https://communities.intel.com/community/makers/galileo**

Description:
------------

Currently there's only one script, which will build a SPI package for you, either in *.cap or *.bin format. The former is good for flashing your board from UEFI Shell, the latter is for full-blown one using DediProg or equivalent.

The script follows the steps outlined in the BSP Building Guide. It downloads the full BSP package to the same directory where the script is located, then creates a sub-directory and unpacks everything there, then builds the FW images - and copies them to the script's directory for your convenience. You can see the example command and the outcome below.

CapsuleApp.efi is used to actually flash the capsule file to the board's SPI flash memory.
The script will build it and copy to the script's dir alongside the firmware files themselves.

At the moment the script will not build the Linux kernel, initramfs and grub images for you - you'll need to provide those as command line parameters. If there's an interest among the community, such functionality can be added - feel free to submit a feature request.

Usage:
------

```
build_galileo_fw.sh -k ./path/to/bzImage \
                    -i ./path/to/image-spi-clanton.cpio.lzma \
                    -g ./path/to/grub.efi \
                    -t all \
                    -m 00:11:dd:ff:aa:55
```

expected outcome (some irrelevant files & dirs omitted):

```
user@lnx:~/> l fw/
total 21088
drwxr-sr-x 3 user users    4096 Dec  8 15:40 ./
drwxrwsr-x 8 user users    4096 Dec  8 12:08 ../
-rw-r--r-- 1 user users 5791634 Nov  6 23:11 Board_Support_Package_Sources_for_Intel_Quark_v1.0.1.7z <<< Downloaded file
drwx--S--- 6 user users    4096 Dec  8 15:40 bsp_src_1.0.1/ <<< All action runs there
-rwxr-xr-x 1 user users   12142 Dec  8 15:17 build_galileo_fw.sh* <<< The script
-rw-r--r-- 1 user users 7386512 Dec  8 15:40 Flash-missingPDAT.cap <<< Capsule file for UEFI Shell flashing
-rw-r--r-- 1 user users 8388608 Dec  8 15:40 Flash+PlatformData.bin <<< Full image with platform data for DediProg
-rwxr-xr-x 1 user users   22784 Dec  8 01:39 CapsuleApp.efi* <<< Flashing UEFI application
```
