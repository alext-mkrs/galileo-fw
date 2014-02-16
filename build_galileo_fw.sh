#!/bin/bash
#
# The MIT License (MIT)
#
# Copyright (c) 2013 Alex T <alext.mkrs@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Script for automatic Galileo board SPI firwmare generation
# Author: Alex T <alext.mkrs@gmail.com>

# debug
#set -x

# To avoid error checking for simple cases
set -e

VERSION="2.1.0"

# This one sets all variables we use
# Precondition: all variables have validated values
set_variables() {
    ### Configuration items
    case "$TARGET_BSP_VER" in
        0.7.5)
                BSP_7Z_PKG_URL="http://downloadmirror.intel.com/23171/eng/Board_Support_Package_Sources_for_Intel_Quark_v0.7.5.7z"
                BSP_7Z_PKG_FNAME="Board_Support_Package_Sources_for_Intel_Quark_v0.7.5.7z"
                EDK_PKG_GLOB="*EDKII*"
                EDK_DIR_GLOB="*EDK2*"
                EDK_SYMLINK_NAME="clanton_peak_EDK2"
                ;;
        0.9.0)
                BSP_7Z_PKG_URL="http://downloadmirror.intel.com/23197/eng/Board_Support_Package_Sources_for_Intel_Quark_v0.9.0.7z"
                BSP_7Z_PKG_FNAME="Board_Support_Package_Sources_for_Intel_Quark_v0.9.0.7z"
                EDK_PKG_GLOB="Quark_EDKII*"
                EDK_DIR_GLOB="Quark_EDKII*"
                # We don't need this for 0.9.0, leaving here for consistency
                # EDK_SYMLINK_NAME="Quark_EDKII"
                ;;
    esac

    SYSIMAGE_DIR_GLOB="sysimage*"
    SYSIMAGE_REL_DIR_GLOB="sysimage*release"

    SPITOOLS_DIR_GLOB="spi-flash-tools*"

    # Various filenames used throughout the process
    TARBALL_EXT="tar.gz"
    FW_BIN_NOPDATA_FNAME="Flash-missingPDAT.bin"
    FW_BIN_PDATA_FNAME="Flash+PlatformData.bin"
    FW_CAP_FNAME="Flash-missingPDAT.cap"
    PDATA_INI_FNAME="my-platform-data.ini"

    # Directory where all actions will take place
    BSP_DIR="bsp_src_${TARGET_BSP_VER}"
    # Absolute path to the script's directory
    BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    # Galileo platform data values for bin image
    # As per the BSP Building Guide
    G_PLTF_TYPE_DVALUE="6"
    G_MRC_PARAMS_ID="6"
    G_MRC_PARAMS_DVALUE="MRC/kipsbay-fabD.v1.bin"
    # Your board's MAC is in G_MAC_0_DVALUE
    # This one isn't used on Galileo
    G_MAC_1_DVALUE="02FFFFFFFF01"

    # Auxilliary tools used by the script
    SZ_EXE=$( which 7z )
    WGET_EXE=$( which wget )
    TAR_EXE=$( which tar )
    SED_EXE=$( which sed )
    AWK_EXE=$( which awk )
}

check_prerequisites() {
    for tool in $SZ_EXE $WGET_EXE $TAR_EXE $SED_EXE $AWK_EXE; do
        if [ ! -x $tool ]; then
            echo "### One of the prerequisite utilities is not installed, please install it and try again."
            echo "### I need 7-zip (7z), wget, tar, sed and awk to run."
            exit 1
        fi
    done
}

# Utility function
# Unpacks the tarball provided in $1 into current dir
unpack_tarball() {
    if [ -n $1 ]; then
        echo "### Unpacking $1..."
        $TAR_EXE xzvf $1 > /dev/null
        echo "### $1 successfully unpacked!"
    else
        echo "### Empty parameter passed to unpack_pkg(), cannot proceed"
        exit 1
    fi  
}

usage() {
    cat <<EOFUSAGE
Usage: $0 <options>
Options:
    -b <target BSP version, 0.7.5|0.9.0> (required)
    -k <path to bzImage produced by "bitbake image-spi"> (required)
    -i <path to image-spi-clanton.cpio.lzma produced by "bitbake image-spi"> (required)
    -g <path to grub.efi produced by "bitbake image-spi"> (required)
    -t <target to build, cap|bin|all> (required)
    -m <your board's MAC address from the sticker,e.g. 001320FF164F> (required for "bin" and "all" targets)
    -h this message
    -v version
EOFUSAGE
}

version() {
    echo "Version $VERSION"
}

parse_opts() {
    OPTIND=1
    while getopts "hvk:i:g:t:m:b:" opt; do
        case "$opt" in
            h)
                usage
                exit 0
                ;;
            v)
                version
                exit 0
                ;;
            k)
                BZIMAGE_FNAME="$OPTARG"
                ;;
            i)
                INITRAMFS_FNAME="$OPTARG"
                ;;
            g)
                GRUB_FNAME="$OPTARG"
                ;;
            t)
                TARGET="$OPTARG"
                ;;
            m)
                G_MAC_0_DVALUE="$OPTARG"
                ;;
            b)
                TARGET_BSP_VER="$OPTARG"
                ;;
            ?)
                usage
                exit 1
                ;;
        esac
    done

    if [ $OPTIND -eq 1 ]; then
        usage
        exit 1
    fi

    for fname in "$BZIMAGE_FNAME" "$INITRAMFS_FNAME" "$GRUB_FNAME"; do
        if [ -z "$fname" ]; then
            echo "### One of the required file parameters is empty or not provided, cannot proceed"
            usage
            exit 1
        fi
        if [ ! -r "$fname" ]; then
            echo "### File '$fname' doesn't exist or unreadable, cannot proceed"
            exit 1
        fi
    done

    # Due to the fact we change directories during building, we want absolute paths
    BZIMAGE_FNAME="$( cd "$( dirname "${BZIMAGE_FNAME}" )" && pwd )"/"$( basename "${BZIMAGE_FNAME}" )"
    INITRAMFS_FNAME="$( cd "$( dirname "${INITRAMFS_FNAME}" )" && pwd )"/"$( basename "${INITRAMFS_FNAME}" )"
    GRUB_FNAME="$( cd "$( dirname "${GRUB_FNAME}" )" && pwd )"/"$( basename "${GRUB_FNAME}" )"

    if [ "$TARGET" != "cap" -a "$TARGET" != "bin" -a "$TARGET" != "all" ]; then
        echo "### Unknown target firmware file type '$TARGET', cannot proceed"
        exit 1
    fi

    if [ \( "$TARGET" == "bin" -o "$TARGET" == "all" \) -a -z "$G_MAC_0_DVALUE" ]; then
        echo "### MAC address of your board is required for 'bin' and 'all' targets, cannot proceed"
        usage
        exit 1
    fi

    # Remove colons from MAC address, if any
    G_MAC_0_DVALUE=$( echo $G_MAC_0_DVALUE|sed -e 's/://g' )

    if [ \( "$TARGET_BSP_VER" != "0.7.5" -a "$TARGET_BSP_VER" != "0.9.0" \) -o -z "$TARGET_BSP_VER" ]; then
        echo "### Valid target BSP version is required, cannot proceed"
        usage
        exit 1
    fi
}

download_package() {
    cd $BASEDIR
    # Download BSP package
    if [ ! -e $BSP_7Z_PKG_FNAME ]; then
        echo "### Downloading the package..."
        $WGET_EXE $BSP_7Z_PKG_URL
        if [ $? -ne 0 ]; then
            echo "### Couldn't download the BSP package from '$BSP_7Z_PKG_URL'"
            exit 1
        fi
        echo "### Downloaded successfully!"
    else
        echo "### Package is already downloaded, skipping download"
    fi
}

unpack_package() {
    cd $BASEDIR
    # Unpack BSP 7z package into predefined dir
    echo "### Unpacking downloaded package..."
    $SZ_EXE e -y -o$BSP_DIR $BSP_7Z_PKG_FNAME > /dev/null
    if [ $? -ne 0 ]; then
        echo "### Couldn't unpack the BSP package file '$BSP_7Z_PKG_FNAME' into '$BASEDIR/$BSP_DIR'"
        exit 1
    fi
    echo "### Unpacked to '$BASEDIR/$BSP_DIR' successfully!"
}

unpack_tools() {
    # Unpack tools
    cd $BASEDIR/$BSP_DIR
    for package in $SYSIMAGE_DIR_GLOB.$TARBALL_EXT \
                   $EDK_PKG_GLOB.$TARBALL_EXT \
                   $SPITOOLS_DIR_GLOB.$TARBALL_EXT; do
        unpack_tarball $package
    done
}

# Creates proper symlinks, copies files
# Precondition: bzImage, initramfs and grub filenames must be absolute
build_file_structure() {
    cd $BASEDIR/$BSP_DIR
    # Ensure file paths in sysimage's layout.conf are correct
    case "$TARGET_BSP_VER" in
        0.7.5)
                # In 0.7.5 we do it manually
                ln -f -s $EDK_DIR_GLOB/ $EDK_SYMLINK_NAME
                ;;
        0.9.0)
                # In 0.9.0 we have a script, which does it for us
                ./$SYSIMAGE_DIR_GLOB/create_symlinks.sh
                ;;
    esac

    # Copies image-spi files into our build dir
    # Precondition: files exist and readable
    cp $BZIMAGE_FNAME $BASEDIR/$BSP_DIR/
    cp $INITRAMFS_FNAME $BASEDIR/$BSP_DIR/
    cp $GRUB_FNAME $BASEDIR/$BSP_DIR/
}

generate_configs() {
    # This takes care about grub, kernel and initramfs.
    # We assume they're in the $BSP_DIR and copy them from where they
    # actually are elsewhere in the script
    # When the feature of actually building them is implemented
    # we will need to add a "meta-clanton" symlink similar to EDK
    # and probably adjust this piece
    cd $BASEDIR/$BSP_DIR/$SYSIMAGE_DIR_GLOB/$SYSIMAGE_REL_DIR_GLOB/

    # It's rather an overkill, 0.7.5 and 0.9.0 share all but one line,
    # but this is a forward-looking setup, assuming they'll change more things in the future
    case "$TARGET_BSP_VER" in
        0.7.5)
                sed -i.orig -r \
                    -e 's#^item_file=.+bzImage#item_file=\.\./\.\./bzImage#' \
                    -e 's#^item_file=.+image-spi-clanton.cpio.lzma#item_file=\.\./\.\./image-spi-clanton.cpio.lzma#' \
                    -e 's#^item_file=.+grub.efi#item_file=\.\./\.\./grub.efi#' \
                    layout.conf
                ;;
        0.9.0)
                sed -i.orig -r \
                    -e 's#^item_file=.+bzImage#item_file=\.\./\.\./bzImage#' \
                    -e 's#^item_file=.+image-spi-clanton.cpio.lzma#item_file=\.\./\.\./image-spi-galileo-clanton.cpio.lzma#' \
                    -e 's#^item_file=.+grub.efi#item_file=\.\./\.\./grub.efi#' \
                    layout.conf
                ;;
        esac

    if [ "$1" == "bin" -o "$1" == "all" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! Please note that platform data will be generated for Galileo/Kips Bay Fab D (blue) board !!!"
        echo "!!! If you flash the resulting image to the board of another type it may brick it            !!!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

        # Prepare platform-data.ini
        cd $BASEDIR/$BSP_DIR/$SPITOOLS_DIR_GLOB/platform-data/
        $AWK_EXE \
            -v pt_dv=$G_PLTF_TYPE_DVALUE \
            -v mp_id=$G_MRC_PARAMS_ID \
            -v mp_dv=$G_MRC_PARAMS_DVALUE \
            -v mac0=$G_MAC_0_DVALUE \
            -v mac1=$G_MAC_1_DVALUE \
            'BEGIN { RS=ORS="\r\n"; FS=OFS="="; }; \
             /^\s*\[/ { section=$1; gsub("[][]","",section); }; \
             section ~ /Platform Type/ && $1 == "data.value" { $2=pt_dv }; \
             section ~ /Mrc Params/ && $1 == "id" { $2=mp_id }; \
             section ~ /Mrc Params/ && $1 == "data.value" { $2=mp_dv }; \
             section ~ /MAC address 0/ && $1 == "data.value" { $2=toupper(mac0) }; \
             section ~ /MAC address 1/ && $1 == "data.value" { $2=toupper(mac1) }; \
             1' \
            sample-platform-data.ini \
            > $PDATA_INI_FNAME
        echo "### Platform data file '$( pwd )/$PDATA_INI_FNAME' written successfully"
    fi
}

build_fw() {
    case "$1" in
        bin)
            build_fw_bin
            ;;
        cap)
            build_fw_cap
            ;;
        all)
            # AFAIU bin actually does the same, but just in case
            build_fw_cap
            build_fw_bin
            ;;
    esac
}

build_fw_cap() {
    echo "### Building capsule file..."
    cd $BASEDIR/$BSP_DIR/$SYSIMAGE_DIR_GLOB/$SYSIMAGE_REL_DIR_GLOB/
    ../../$SPITOOLS_DIR_GLOB/Makefile capsule
    if [ -e $FW_CAP_FNAME ]; then
        cp $FW_CAP_FNAME $BASEDIR
        echo "### Capsule file built and copied to '$BASEDIR/$FW_CAP_FNAME' successfully!"
    else
        echo "### Capsule file '$FW_CAP_FNAME' was not created by the build process - something went wrong"
        exit 1
    fi
}

build_fw_bin() {
    echo "### Building binary file..."
    cd $BASEDIR/$BSP_DIR/$SYSIMAGE_DIR_GLOB/$SYSIMAGE_REL_DIR_GLOB/

    ../../$SPITOOLS_DIR_GLOB/Makefile
    echo "### ...done!"
    echo "### Adding platform data to the file..."
    cd $BASEDIR/$BSP_DIR/$SPITOOLS_DIR_GLOB/platform-data/
    ./platform-data-patch.py \
        -p $PDATA_INI_FNAME \
        -i $BASEDIR/$BSP_DIR/$SYSIMAGE_DIR_GLOB/$SYSIMAGE_REL_DIR_GLOB/$FW_BIN_NOPDATA_FNAME

    if [ -e $FW_BIN_PDATA_FNAME ]; then
        cp $FW_BIN_PDATA_FNAME $BASEDIR
        echo "### Bin file built and copied to '$BASEDIR/$FW_BIN_PDATA_FNAME' successfully!"
    else
        echo "### Bin file '$BASEDIR/$FW_BIN_PDATA_FNAME' was not created by the build process - something went wrong"
        exit 1
    fi
}

build_edk_fw() {
    echo "### Building EDK firmware and CapsuleApp.efi..."
    cd $BASEDIR/$BSP_DIR/$EDK_DIR_GLOB/
    ./svn_setup.py
    svn update
    # BSP Build Guide has buildallconfigs as the default,
    # but this doesn't really make sense - it builds 3 surplus configs we'll never use
    #./buildallconfigs.sh GCC47 QuarkPlatform
    # The below is based on the buildallconfigs' contents,
    # but builds only PLAIN RELEASE config.
    GCC_VER=""
    GCC_VER=$( gcc --version |head -1|sed -r -e 's#.*([[:digit:]]\.[[:digit:]])\.[[:digit:]].*#\1#' -e 's/\.//' )
    if [ -z "$GCC_VER" ]; then
        echo "### Cannot determine GCC version, cannot proceed!"
        exit 1
    fi

    case "$GCC_VER" in
        43|44|45|46|47)
                        echo "### Supported GCC version found, proceeding..."
                        ;;
                     *)
                        read -n 1 \
                             -p "### Attention, unsupported GCC version '$GCC_VER' detected, press Ctrl+C if you DO NOT want to proceed, any other key to continue!"
                        ;;
    esac

    ./quarkbuild.sh -r32 "GCC${GCC_VER}" QuarkPlatform
    cd Build/*Platform/
    mkdir -p PLAIN/
    ln -s RELEASE_GCC* RELEASE_GCC
    rm -rf PLAIN/*
    mv RELEASE_GCC* PLAIN/
    cp PLAIN/RELEASE_GCC*/FV/Applications/CapsuleApp.efi $BASEDIR
    echo "### Copied CapsuleApp.efi to $BASEDIR successfully!"
}

### Main
parse_opts "$@"
set_variables
check_prerequisites
download_package
unpack_package
unpack_tools
if [ "$TARGET_BSP_VER" == "0.9.0" ]; then
    build_edk_fw
fi
build_file_structure
generate_configs "$TARGET"
build_fw "$TARGET"

