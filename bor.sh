#!/bin/bash
{ # Safety wrapper: prevent execution if script is truncated
set -e

# --- Utility Functions ---
oops() {
    echo "CRITICAL ERROR: $@" >&2
    exit 1
}

# Trap for cleanup on exit or interruption
cleanup() {
    [ -d "$tmpDir" ] && rm -rf "$tmpDir"
}
trap cleanup EXIT INT QUIT TERM

# --- System Validation ---
require_util() {
    command -v "$1" > /dev/null 2>&1 || \
        oops "Required utility '$1' is missing. Please install it to $2."
}

umask 0022
tmpDir="$(mktemp -d -t bor-installer-XXXXXXXXXXX)" || oops "Failed to create temporary directory"

# --- Default Parameters ---
VERSION="0.3.0"
NETWORK="mainnet"
NODETYPE="sentry"

# --- Argument Parsing ---
helpFunction() {
    echo "Polygon Bor Automated Installer"
    echo "Usage: $0 [-h] [version] [network] [nodetype]"
    echo "Networks: mainnet, mumbai, amoy"
    echo "Node Types: sentry, validator, archive, bootnode"
    exit 0
}

while getopts "h" opt; do
    case "$opt" in
        h) helpFunction ;;
        *) oops "Invalid option used." ;;
    esac
done

# Dynamic version/network/nodetype assignment
[ -n "$1" ] && VERSION="${1#v}" # Strip 'v' prefix if present
[ -n "$2" ] && NETWORK="$2"
[ -n "$3" ] && NODETYPE="$3"

[Image of Polygon PoS architecture: Bor and Heimdall relationship]

# --- Binary Selection Logic ---
# Detect Architecture and OS
ARCH="$(uname -m)"
OS="$(uname -s)"
BASE_URL="https://github.com/maticnetwork/bor/releases/download/v${VERSION}"

echo "Targeting: Bor v${VERSION} on ${NETWORK} (${NODETYPE} configuration)"

# Determine Package Type and Filename
case "${OS}.${ARCH}" in
    Linux.x86_64)  PK_ARCH="amd64" ;;
    Linux.aarch64) PK_ARCH="arm64" ;;
    *) oops "Unsupported Platform: ${OS} ${ARCH}. Bor binaries are optimized for Linux x86_64/ARM64." ;;
esac

# Detect Package Manager
if command -v dpkg &>/dev/null; then
    PK_TYPE="deb"
    BINARY_NAME="bor-${VERSION}-${PK_ARCH}.deb"
    PROFILE_NAME="bor-${NETWORK}-${NODETYPE}-config_v${VERSION}-${PK_ARCH}.deb"
elif command -v rpm &>/dev/null; then
    PK_TYPE="rpm"
    BINARY_NAME="bor-${VERSION}-${PK_ARCH}.rpm"
    PROFILE_NAME="bor-${NETWORK}-${NODETYPE}-config_v${VERSION}-${PK_ARCH}.rpm"
else
    PK_TYPE="tar.gz"
    BINARY_NAME="bor_${VERSION}_linux_${PK_ARCH}.tar.gz"
fi

# --- Download Phase ---
if command -v curl >/dev/null 2>&1; then
    fetch() { curl -L "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q "$1" -O "$2"; }
else
    oops "Neither 'curl' nor 'wget' found. Please install one to download binaries."
fi

echo "Downloading packages to temporary storage..."
fetch "${BASE_URL}/${BINARY_NAME}" "${tmpDir}/${BINARY_NAME}" || oops "Binary download failed."

if [ -n "$PROFILE_NAME" ] && [[ "$VERSION" > "0.3" ]]; then
    fetch "${BASE_URL}/${PROFILE_NAME}" "${tmpDir}/${PROFILE_NAME}" || echo "Warning: Profile package not found, skipping..."
fi

[Image of Polygon node synchronization process and snapshot management]

# --- Installation Phase ---
echo "Applying installation (sudo access may be required)..."
case "$PK_TYPE" in
    deb)
        sudo dpkg -r bor || true
        sudo dpkg -i "${tmpDir}/${BINARY_NAME}"
        [ -f "${tmpDir}/${PROFILE_NAME}" ] && sudo dpkg -i "${tmpDir}/${PROFILE_NAME}"
        ;;
    rpm)
        sudo rpm -e bor || true
        sudo rpm -i --force "${tmpDir}/${BINARY_NAME}"
        [ -f "${tmpDir}/${PROFILE_NAME}" ] && sudo rpm -i --force "${tmpDir}/${PROFILE_NAME}"
        ;;
    tar.gz)
        tar -xzf "${tmpDir}/${BINARY_NAME}" -C "$tmpDir"
        sudo cp "${tmpDir}/bor" /usr/local/bin/bor
        ;;
esac

# --- Verification ---
echo "Verifying installation..."
/usr/local/bin/bor version || oops "Verification failed. Binary may be corrupted."

echo "SUCCESS: Bor v${VERSION} has been installed successfully."
echo "Config directory: /var/lib/bor/config.toml (if profile was installed)"

} # End of safety wrapper
