#!/bin/bash
#
# Kindly provided by Alexis Murzeau <amubtdx@gmail.com>
# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=975475#22
# Adapted by Marc Dequènes (Duck) <Duck@DuckCorp.org>

set -e -o pipefail


PACKAGE=$1
DH_PKG_DIR=debian/.debhelper/${PACKAGE}/


get_buildid()
{
    local FILE=$1

    llvm-readobj --coff-debug-directory $FILE | awk '/PDBGUID:/ { $1=""; gsub(/[^0-9A-F]+/, ""); print; exit }'
}

strip_and_create_debug()
{
    local BINARY_FILE=$1
    local BUILDID=$2
    local DEBUG_FILE=${DH_PKG_DIR}/dbgsym-root/usr/lib/debug/.build-id/${BUILDID:0:2}/${BUILDID:2}.debug
    local DEBUG_FILE_DIR=$(dirname $DEBUG_FILE)
    local DEBUG_FILE_NAME=$(basename $DEBUG_FILE)
    local BINARY_FILE_DIR=$(dirname $BINARY_FILE)
    local BINARY_FILE_NAME=$(basename $BINARY_FILE)

    mkdir -p $DEBUG_FILE_DIR

    # Sequence made according to dh_strip but using binutils-mingw-w64-x86-64 tools
    # https://salsa.debian.org/debian/debhelper/-/blob/main/dh_strip

    # Note: --compress-debug-sections is not supported by winedbg and will cause a crash
    ${DEB_HOST_GNU_CPU}-w64-mingw32-objcopy --only-keep-debug "$BINARY_FILE" "$DEBUG_FILE"
    chmod 0644 "$DEBUG_FILE"
    ${DEB_HOST_GNU_CPU}-w64-mingw32-strip --remove-section=.comment --remove-section=.note --strip-unneeded "$BINARY_FILE"
    # It is not possible to specify a path that does not exist to set the debug link with objcopy.
    # Instead, using a filename without component directory will trigger a lookup in various locations
    # including /usr/lib/debug/
    cp "$DEBUG_FILE" "${BINARY_FILE_DIR}/${DEBUG_FILE_NAME}"
    pushd "${BINARY_FILE_DIR}"
    ${DEB_HOST_GNU_CPU}-w64-mingw32-objcopy --add-gnu-debuglink "$(basename $DEBUG_FILE_NAME)" "$BINARY_FILE_NAME"
    popd
    rm "${BINARY_FILE_DIR}/${DEBUG_FILE_NAME}"
}


mkdir -p ${DH_PKG_DIR}

for FILE in $(find debian/${PACKAGE}/usr/lib -name "*.dll.so"); do
    BUILDID=$(get_buildid $FILE)
    echo "Striping '${FILE}' with build-id '${BUILDID}'"
    strip_and_create_debug $FILE $BUILDID
    # list of build-ids, later used by dh_gencontrol to create the Build-Ids package header
    echo $BUILDID >>${DH_PKG_DIR}/dbgsym-build-ids.tmp
done

cat ${DH_PKG_DIR}/dbgsym-build-ids.tmp | sort | paste -sd ' ' > ${DH_PKG_DIR}/dbgsym-build-ids
rm ${DH_PKG_DIR}/dbgsym-build-ids.tmp


# To debug a program, you can do:
# $ winedbg --gdb --no-start --port 2345 program.exe
# [...]
#
# $ gdb program.exe
# [...]
# (gdb) target remote localhost:2345

# gdb must be used instead of ${DEB_HOST_GNU_CPU}-w64-mingw32-gdb (else winedbg will have this error:
# 0108:err:winedbg:packet_query Unhandled query "GetTIBAddr:110"
