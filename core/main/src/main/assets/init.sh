#!/bin/sh
# Note: do NOT use `set -e` here. Several operations below (apk update, apk add,
# identity file checks) are allowed to fail without killing the terminal —
# e.g. when the device has no network. We handle each failure explicitly.

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/share/bin:/usr/share/sbin:/usr/local/bin:/usr/local/sbin:/system/bin:/system/xbin
export HOME=/root
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PIP_BREAK_SYSTEM_PACKAGES=1

mkdir -p "$HOME"

if [ ! -s /etc/resolv.conf ]; then
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
fi

sanitize_name() {
    cleaned=$(printf "%s" "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-32)
    [ -n "$cleaned" ] && printf "%s" "$cleaned"
}

write_identity_files() {
    user_name=$(sanitize_name "$1")
    host_name=$(sanitize_name "$2")
    [ -z "$user_name" ] && user_name="user"
    [ -z "$host_name" ] && host_name="terlinux"

    cat > "$HOME/.terlinux_identity" <<EOF
TERLINUX_USER='$user_name'
TERLINUX_HOST='$host_name'
EOF

    echo "$host_name" > /etc/hostname
    cat > /etc/hosts <<EOF
127.0.0.1 localhost $host_name
::1 localhost $host_name
EOF

    mkdir -p /etc/profile.d
    cat > /etc/profile.d/terlinux-identity.sh <<EOF
export TERLINUX_USER='$user_name'
export TERLINUX_HOST='$host_name'
export USER='$user_name'
export LOGNAME='$user_name'
export HOSTNAME='$host_name'
case "\$-" in
  *i*) PS1='$user_name@$host_name:\\w# ' ;;
esac
EOF

    cat > "$HOME/.bash_profile" <<EOF
[ -f /etc/profile ] && . /etc/profile
[ -f ~/.bashrc ] && . ~/.bashrc
EOF

    cat > "$HOME/.zprofile" <<EOF
export TERLINUX_USER='$user_name'
export TERLINUX_HOST='$host_name'
export USER='$user_name'
export LOGNAME='$user_name'
export HOSTNAME='$host_name'
PROMPT='$user_name@$host_name:%~# '
EOF

    mkdir -p "$HOME/.config/fish"
    cat > "$HOME/.config/fish/config.fish" <<EOF
set -gx TERLINUX_USER '$user_name'
set -gx TERLINUX_HOST '$host_name'
set -gx USER '$user_name'
set -gx LOGNAME '$user_name'
set -gx HOSTNAME '$host_name'
function fish_prompt
    set_color cyan
    printf '$user_name'
    set_color normal
    printf '@'
    set_color green
    printf '$host_name'
    set_color normal
    printf ':'
    set_color blue
    prompt_pwd
    set_color normal
    printf '# '
end
EOF
}

install_identity_tool() {
    cat > /usr/local/bin/terlinux-identity <<'EOF'
#!/bin/sh
sanitize_name() {
    cleaned=$(printf "%s" "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-32)
    [ -n "$cleaned" ] && printf "%s" "$cleaned"
}

write_identity_files() {
    user_name=$(sanitize_name "$1")
    host_name=$(sanitize_name "$2")
    [ -z "$user_name" ] && user_name="user"
    [ -z "$host_name" ] && host_name="terlinux"

    cat > "$HOME/.terlinux_identity" <<EOT
TERLINUX_USER='$user_name'
TERLINUX_HOST='$host_name'
EOT
    echo "$host_name" > /etc/hostname
    cat > /etc/hosts <<EOT
127.0.0.1 localhost $host_name
::1 localhost $host_name
EOT
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/terlinux-identity.sh <<EOT
export TERLINUX_USER='$user_name'
export TERLINUX_HOST='$host_name'
export USER='$user_name'
export LOGNAME='$user_name'
export HOSTNAME='$host_name'
case "\$-" in
  *i*) PS1='$user_name@$host_name:\\w# ' ;;
esac
EOT
    cat > "$HOME/.bash_profile" <<EOT
[ -f /etc/profile ] && . /etc/profile
[ -f ~/.bashrc ] && . ~/.bashrc
EOT
    cat > "$HOME/.zprofile" <<EOT
export TERLINUX_USER='$user_name'
export TERLINUX_HOST='$host_name'
export USER='$user_name'
export LOGNAME='$user_name'
export HOSTNAME='$host_name'
PROMPT='$user_name@$host_name:%~# '
EOT
    mkdir -p "$HOME/.config/fish"
    cat > "$HOME/.config/fish/config.fish" <<EOT
set -gx TERLINUX_USER '$user_name'
set -gx TERLINUX_HOST '$host_name'
set -gx USER '$user_name'
set -gx LOGNAME '$user_name'
set -gx HOSTNAME '$host_name'
function fish_prompt
    set_color cyan
    printf '$user_name'
    set_color normal
    printf '@'
    set_color green
    printf '$host_name'
    set_color normal
    printf ':'
    set_color blue
    prompt_pwd
    set_color normal
    printf '# '
end
EOT
}

printf 'Terlinux identity setup\n'
printf 'User name [user]: '
read -r user_name
printf 'Host name [terlinux]: '
read -r host_name
[ -z "$user_name" ] && user_name=user
[ -z "$host_name" ] && host_name=terlinux
write_identity_files "$user_name" "$host_name"
printf 'Saved. Open a new session or run: exec $SHELL -l\n'
EOF
    chmod 755 /usr/local/bin/terlinux-identity
}

first_identity_setup() {
    install_identity_tool
    if [ ! -f "$HOME/.terlinux_identity" ] && [ -t 0 ]; then
        printf '\nTerlinux first setup\n'
        printf 'This changes the visible terminal prompt only. The Linux container still runs through proot.\n\n'
        printf 'User name [user]: '
        read -r user_name
        printf 'Host name [terlinux]: '
        read -r host_name
        [ -z "$user_name" ] && user_name=user
        [ -z "$host_name" ] && host_name=terlinux
        write_identity_files "$user_name" "$host_name"
        printf '\nSaved identity: %s@%s\n\n' "$(sanitize_name "$user_name")" "$(sanitize_name "$host_name")"
    elif [ -f "$HOME/.terlinux_identity" ]; then
        . "$HOME/.terlinux_identity"
        write_identity_files "$TERLINUX_USER" "$TERLINUX_HOST"
    fi
}

install_packages() {
    missing=""
    for pkg in "$@"; do
        if ! dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null | grep -qx installed; then
            missing="$missing $pkg"
        fi
    done

    if [ -n "$missing" ]; then
        echo "Installing packages:$missing"
        apt-get update || echo "apt-get update failed; continuing"
        apt-get install -y $missing || return 1
    fi
    return 0
}

# Base compatibility packages. Keep this list small; optional shells are installed only when selected.
install_packages bash nano
first_identity_setup

# Fix Android linker warning in some proot builds.
if [ ! -f /linkerconfig/ld.config.txt ]; then
    mkdir -p /linkerconfig
    touch /linkerconfig/ld.config.txt
fi

select_shell() {
    case "${TERLINUX_DEFAULT_SHELL:-bash}" in
        bash|sh)
            SELECTED_SHELL=/bin/bash
            SELECTED_PKG=""
            ;;
        fish)
            SELECTED_SHELL=/usr/bin/fish
            SELECTED_PKG=fish
            ;;
        zsh)
            SELECTED_SHELL=/bin/zsh
            SELECTED_PKG=zsh
            ;;
        *)
            echo "Unknown shell '${TERLINUX_DEFAULT_SHELL}', falling back to bash"
            SELECTED_SHELL=/bin/bash
            SELECTED_PKG=""
            ;;
    esac
}

select_shell

if [ -n "$SELECTED_PKG" ] && [ ! -x "$SELECTED_SHELL" ]; then
    if ! install_packages "$SELECTED_PKG"; then
        echo "Failed to install shell package '$SELECTED_PKG', falling back to bash"
        SELECTED_SHELL=/bin/bash
    fi
fi

if [ ! -x "$SELECTED_SHELL" ]; then
    echo "Shell '$SELECTED_SHELL' is not executable, falling back to bash"
    SELECTED_SHELL=/bin/bash
fi

export SHELL="$SELECTED_SHELL"
cd "$HOME"

if [ "$#" -eq 0 ]; then
    exec "$SELECTED_SHELL" -l
else
    exec "$@"
fi
