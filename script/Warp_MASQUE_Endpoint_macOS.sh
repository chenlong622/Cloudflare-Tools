#!/bin/bash
# ---- Proxy-free execution environment ----
# Run this tool without inheriting HTTP/HTTPS/SOCKS proxy environment variables.
# This does NOT modify the user's shell configuration or system proxy settings.
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
unset http_proxy https_proxy all_proxy
unset FTP_PROXY ftp_proxy
unset NO_PROXY no_proxy
export WARP_NO_PROXY_ENV=1

# Cloudflare WARP MASQUE-H2 Node Generator
# by Artemis Lab (From YouTube)
# macOS: Intel + Apple Silicon

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"
WARPSCOUT_DIR="$TOOLS_DIR/warpscout"
WARPSCOUT_EXE="$WARPSCOUT_DIR/warpscout"
ACCOUNT_FILE="$WARPSCOUT_DIR/warpscout-account.json"
REPORT_FILE="$WARPSCOUT_DIR/scan-report.txt"
BEST_FILE="$WARPSCOUT_DIR/best-mihomo.yaml"
OUTPUT_FILE="$SCRIPT_DIR/warp-multi.yaml"
ARCHIVE_FILE="$TOOLS_DIR/warpscout-download.tar.gz"

R2_BASE="https://pub-453eabf12730419aa802d8e819e1333d.r2.dev"

print_error() {
    echo
    echo "[ERROR] $1"
    echo
    exit 1
}

quote_yaml() {
    local value="$1"
    value=${value//\'/\'\'}
    printf "'%s'" "$value"
}

get_yaml_value() {
    local file="$1"
    local key="$2"
    awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
            sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "")
            print
            exit
        }
    ' "$file" | tr -d "\"'"
}

clear 2>/dev/null || true
printf '%s\n' '========================================'
printf '%s\n' '      Cloudflare WARP MASQUE-H2'
printf '%s\n' '           Node Generator'
printf '%s\n' ''
printf '%s\n' '       by Artemis Lab (From YouTube) V1.0'
printf '%s\n' '========================================'

# macOS check
OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    print_error "This script is for macOS only. Detected: $OS"
fi

# Detect CPU architecture.
ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        PLATFORM="darwin_arm64"
        ARCH_LABEL="Apple Silicon (arm64)"
        ;;
    x86_64)
        PLATFORM="darwin_amd64"
        ARCH_LABEL="Intel (x86_64)"
        ;;
    *)
        print_error "Unsupported Mac CPU architecture: $ARCH"
        ;;
esac

WARPSCOUT_URL="$R2_BASE/warpscout_0.16.0_${PLATFORM}.tar.gz"

printf '\n%s\n' '[1/5] Preparing warpscout...'
printf '%s\n' "Detected: $ARCH_LABEL"

mkdir -p "$WARPSCOUT_DIR" || print_error "Could not create the tools/warpscout directory."

if [ ! -f "$WARPSCOUT_EXE" ]; then
    printf '%s\n' "Downloading warpscout 0.16.0 from R2..."
    printf '%s\n' "Source: $WARPSCOUT_URL"

    rm -f "$ARCHIVE_FILE"
    if ! curl --noproxy "*" -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$ARCHIVE_FILE" "$WARPSCOUT_URL"; then
        rm -f "$ARCHIVE_FILE"
        print_error "Could not download warpscout from R2. Check the network connection and try again."
    fi

    if [ ! -s "$ARCHIVE_FILE" ]; then
        rm -f "$ARCHIVE_FILE"
        print_error "R2 returned an empty warpscout download."
    fi

    # Extract into the warpscout directory. The archive may contain a wrapper folder,
    # so find the actual binary afterwards.
    if ! tar -xzf "$ARCHIVE_FILE" -C "$WARPSCOUT_DIR"; then
        rm -f "$ARCHIVE_FILE"
        print_error "Could not extract warpscout."
    fi
    rm -f "$ARCHIVE_FILE"

    if [ ! -f "$WARPSCOUT_EXE" ]; then
        EXTRACTED="$(find "$WARPSCOUT_DIR" -type f -name 'warpscout' -print -quit 2>/dev/null)"
        if [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "$WARPSCOUT_EXE" ]; then
            mv "$EXTRACTED" "$WARPSCOUT_EXE" || print_error "Could not move warpscout into the expected location."
        fi
    fi
else
    printf '%s\n' 'Existing warpscout found; download skipped.'
fi

if [ ! -f "$WARPSCOUT_EXE" ]; then
    print_error "warpscout was not found after extraction."
fi

chmod +x "$WARPSCOUT_EXE" || print_error "Could not make warpscout executable."

# Files downloaded from the Internet can receive macOS quarantine metadata.
# Ignore the error when the attribute is not present.
if command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$WARPSCOUT_EXE" 2>/dev/null || true
fi

printf '\n%s\n' '[2/5] Checking the WARP account...'
if [ -f "$ACCOUNT_FILE" ]; then
    printf '%s\n' 'Existing WARP account found; registration skipped.'
else
    printf '%s\n' 'Registering a new WARP account. Please wait...'
    if ! (cd "$WARPSCOUT_DIR" && "$WARPSCOUT_EXE" register); then
        print_error "WARP account registration failed. Check your network and try again."
    fi
    if [ ! -f "$ACCOUNT_FILE" ]; then
        print_error "Registration completed but warpscout-account.json was not created."
    fi
fi
printf '%s\n' 'WARP account is ready.'

printf '\n%s\n' '[3/5] Scanning MASQUE-H2 endpoints...'
printf '%s\n' 'This scan tests about 280 endpoints. Please wait...'
rm -f "$REPORT_FILE" "$BEST_FILE"

if ! (cd "$WARPSCOUT_DIR" && "$WARPSCOUT_EXE" scan -p masque-h2 -n 20 -o scan-report.txt -conf best-mihomo.yaml -conf-type mihomo); then
    print_error "MASQUE-H2 scan failed. Check your network and try again."
fi

if [ ! -f "$REPORT_FILE" ]; then
    print_error "The scan completed but scan-report.txt was not created."
fi
if [ ! -f "$BEST_FILE" ]; then
    print_error "The scan completed but best-mihomo.yaml was not created."
fi

printf '\n%s\n' 'Scan completed.'

# Parse the ENDPOINT table from scan-report.txt, deduplicate endpoints,
# then select up to 16 endpoints with the lowest endpoint ping.
SELECTED_FILE="$WARPSCOUT_DIR/selected-endpoints.tmp"
rm -f "$SELECTED_FILE"

awk '
    /^ENDPOINT[[:space:]]+/ { in_table=1; next }
    /^#[[:space:]]+[0-9]+[[:space:]]+torn down[[:space:]]*$/ { exit }
    in_table {
        if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ && ($2 ~ /^[0-9]+(\.[0-9]+)?ms$/ || $2 == "?")) {
            print $1 "\t" $2
        }
    }
' "$REPORT_FILE" \
    | awk '
        !seen[$1]++ {
            ping=999999999
            if ($2 != "?") {
                ping=$2
                sub(/ms$/, "", ping)
            }
            print ping "\t" $1
        }
    ' \
    | sort -n -k1,1 -k2,2 \
    | head -n 16 \
    | cut -f2 > "$SELECTED_FILE"

ENDPOINT_COUNT="$(awk 'END {print NR+0}' "$SELECTED_FILE")"
if [ "$ENDPOINT_COUNT" -eq 0 ]; then
    rm -f "$SELECTED_FILE"
    print_error "No working MASQUE-H2 endpoint was found in this scan."
fi

# Count all unique working endpoints for the same status message used by the Windows version.
WORKING_COUNT="$(
    awk '
        /^ENDPOINT[[:space:]]+/ { in_table=1; next }
        /^#[[:space:]]+[0-9]+[[:space:]]+torn down[[:space:]]*$/ { exit }
        in_table {
            if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ && ($2 ~ /^[0-9]+(\.[0-9]+)?ms$/ || $2 == "?")) {
                print $1
            }
        }
    ' "$REPORT_FILE" | sort -u | wc -l | tr -d ' '
)"

printf '%s\n' "Working endpoints found: $WORKING_COUNT"
printf '%s\n' 'Selecting up to 16 endpoints with the lowest endpoint ping...'

printf '\n%s\n' '[4/5] Generating the Mihomo configuration...'

PRIVATE_KEY="$(get_yaml_value "$BEST_FILE" 'private-key')"
PUBLIC_KEY="$(get_yaml_value "$BEST_FILE" 'public-key')"
IP="$(get_yaml_value "$BEST_FILE" 'ip')"
IPV6="$(get_yaml_value "$BEST_FILE" 'ipv6')"
SNI="$(get_yaml_value "$BEST_FILE" 'sni')"

[ -n "$PRIVATE_KEY" ] || print_error "best-mihomo.yaml is missing required field: private-key."
[ -n "$PUBLIC_KEY" ] || print_error "best-mihomo.yaml is missing required field: public-key."
[ -n "$IP" ] || print_error "best-mihomo.yaml is missing required field: ip."
[ -n "$SNI" ] || print_error "best-mihomo.yaml is missing required field: sni."

TEMP_OUTPUT="$OUTPUT_FILE.tmp"
rm -f "$TEMP_OUTPUT"

{
    printf '%s\n' 'mixed-port: 7890'
    printf '%s\n' 'allow-lan: false'
    printf '%s\n' 'mode: rule'
    printf '%s\n' 'log-level: info'
    printf '%s\n' ''
    printf '%s\n' 'proxies:'

    INDEX=0
    while IFS= read -r ENDPOINT; do
        [ -n "$ENDPOINT" ] || continue
        INDEX=$((INDEX + 1))
        NAME=$(printf 'WARP-H2-%02d' "$INDEX")
        SERVER="${ENDPOINT%:*}"
        PORT="${ENDPOINT##*:}"

        printf '  - name: %s\n' "$(quote_yaml "$NAME")"
        printf '%s\n' '    type: masque'
        printf '    server: %s\n' "$SERVER"
        printf '    port: %s\n' "$PORT"
        printf '%s\n' '    network: h2'
        printf '    sni: %s\n' "$(quote_yaml "$SNI")"
        printf '    private-key: %s\n' "$(quote_yaml "$PRIVATE_KEY")"
        printf '    public-key: %s\n' "$(quote_yaml "$PUBLIC_KEY")"
        printf '    ip: %s\n' "$(quote_yaml "$IP")"
        if [ -n "$IPV6" ]; then
            printf '    ipv6: %s\n' "$(quote_yaml "$IPV6")"
        fi
        printf '%s\n' '    udp: true'
        printf '%s\n' '    remote-dns-resolve: true'
        printf '%s\n' '    dns: [1.1.1.1, 1.0.0.1]'
        printf '%s\n' ''
    done < "$SELECTED_FILE"

    printf '%s\n' 'proxy-groups:'
    printf '%s\n' '  - name: WARP-AUTO'
    printf '%s\n' '    type: url-test'
    printf '%s\n' '    proxies:'

    INDEX=0
    while IFS= read -r ENDPOINT; do
        [ -n "$ENDPOINT" ] || continue
        INDEX=$((INDEX + 1))
        printf '      - WARP-H2-%02d\n' "$INDEX"
    done < "$SELECTED_FILE"

    printf '%s\n' '    url: https://www.cloudflare.com/cdn-cgi/trace'
    printf '%s\n' '    interval: 300'
    printf '%s\n' '    tolerance: 50'
    printf '%s\n' ''
    printf '%s\n' 'rules:'
    printf '%s\n' '  - MATCH,WARP-AUTO'
} > "$TEMP_OUTPUT" || {
    rm -f "$TEMP_OUTPUT" "$SELECTED_FILE"
    print_error "Could not write warp-multi.yaml. Check folder permissions."
}

mv -f "$TEMP_OUTPUT" "$OUTPUT_FILE" || {
    rm -f "$TEMP_OUTPUT" "$SELECTED_FILE"
    print_error "Could not create warp-multi.yaml. Check folder permissions."
}

rm -f "$SELECTED_FILE"

if [ ! -f "$OUTPUT_FILE" ]; then
    print_error "Configuration generation failed: warp-multi.yaml was not created."
fi

printf '\n%s\n' '[5/5] Completed.'
printf '\n%s\n' '========================================'
printf '%s\n' '              SUCCESS'
printf '%s\n' '========================================'
printf '\n%s\n' "Selected nodes: $ENDPOINT_COUNT"
printf '\n%s\n' 'Configuration file:'
printf '%s\n' 'warp-multi.yaml'
printf '\n%s\n' 'Import this file into a Mihomo / Clash-compatible client.'
printf '%s\n' 'WARP-AUTO will automatically select a lower-latency node.'
printf '\n'
