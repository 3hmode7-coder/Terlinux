UBUNTU_DIR=$PREFIX/local/ubuntu
ROOTFS_MARKER=$UBUNTU_DIR/.rootfs-ready

mkdir -p "$UBUNTU_DIR"

if [ ! -f "$ROOTFS_MARKER" ]; then
    # Android applications cannot restore the root ownership recorded in the
    # Ubuntu archive. Without these flags tar can then be denied while making
    # its hard links (for example /usr/bin/perl and coreutils commands).
    # Keep the marker absent on failure so the next launch retries extraction.
    if ! tar --no-same-owner --no-same-permissions -xf "$PREFIX/files/ubuntu.tar.gz" -C "$UBUNTU_DIR"; then
        echo "Ubuntu rootfs extraction failed; it will be retried on the next launch." >&2
        exit 1
    fi
    touch "$ROOTFS_MARKER"
fi

[ ! -e "$PREFIX/local/bin/proot" ] && cp "$PREFIX/files/proot" "$PREFIX/local/bin"

# Copy any pre-bundled shared libraries (libtalloc.so.2 etc.) into the local lib dir.
# We use a for loop with an explicit existence check so that if the glob does not
# match anything (e.g. only libtalloc.so.2 is present), we don't try to copy the
# literal string "$PREFIX/files/*.so.2" as a file.
for sofile in "$PREFIX/files/"*.so.2; do
    [ -e "$sofile" ] || continue
    dest="$PREFIX/local/lib/$(basename "$sofile")"
    [ ! -e "$dest" ] && cp "$sofile" "$dest"
done

ARGS="--kill-on-exit"
ARGS="$ARGS -w /"

for system_mnt in /apex /odm /product /system /system_ext /vendor \
 /linkerconfig/ld.config.txt \
 /linkerconfig/com.android.art/ld.config.txt \
 /plat_property_contexts /property_contexts; do

 if [ -e "$system_mnt" ]; then
  system_mnt=$(realpath "$system_mnt")
  ARGS="$ARGS -b ${system_mnt}"
 fi
done
unset system_mnt

ARGS="$ARGS -b /sdcard"
ARGS="$ARGS -b /storage"
ARGS="$ARGS -b /dev"
ARGS="$ARGS -b /data"
ARGS="$ARGS -b /dev/urandom:/dev/random"
ARGS="$ARGS -b /proc"
ARGS="$ARGS -b /sys"
ARGS="$ARGS -b $PREFIX"

if [ -e "/proc/self/fd" ]; then
  ARGS="$ARGS -b /proc/self/fd:/dev/fd"
fi

if [ -e "/proc/self/fd/0" ]; then
  ARGS="$ARGS -b /proc/self/fd/0:/dev/stdin"
fi

if [ -e "/proc/self/fd/1" ]; then
  ARGS="$ARGS -b /proc/self/fd/1:/dev/stdout"
fi

if [ -e "/proc/self/fd/2" ]; then
  ARGS="$ARGS -b /proc/self/fd/2:/dev/stderr"
fi

if [ ! -d "$PREFIX/local/ubuntu/tmp" ]; then
 mkdir -p "$PREFIX/local/ubuntu/tmp"
 chmod 1777 "$PREFIX/local/ubuntu/tmp"
fi
ARGS="$ARGS -b $PREFIX/local/ubuntu/tmp:/dev/shm"

ARGS="$ARGS -r $PREFIX/local/ubuntu"
ARGS="$ARGS -0"
ARGS="$ARGS --link2symlink"
ARGS="$ARGS --sysvipc"
ARGS="$ARGS -L"

exec $LINKER $PREFIX/local/bin/proot $ARGS sh $PREFIX/local/bin/init "$@"
