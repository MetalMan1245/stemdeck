#!/usr/bin/env bash

# ============================================================================
# StemDeck Linux Installer / Uninstaller
#
# Expected files beside this script:
#
#   StemDeck-Linux-x64.tar.gz
#   StemDeck-Linux-x64.NVIDIA.tar.gz
#   stemdeck-logo.png
#
# If both archives exist:
#
#   1 = CPU-only
#   2 = NVIDIA
#
# Installation:
#
#   1 = Global
#      /opt/StemDeck-Linux-x64/
#      /opt/StemDeck-Linux-x64.NVIDIA/
#
#   2 = Local
#      ~/.portable/StemDeck-Linux-x64/
#      ~/.portable/StemDeck-Linux-x64.NVIDIA/
#
# If ~/.config/stemdeck/stemdeck-manifest.txt exists, the script enters
# uninstall mode.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="${HOME}/.config/stemdeck"
MANIFEST="${CONFIG_DIR}/stemdeck-manifest.txt"

DESKTOP_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${DESKTOP_DIR}/stemdeck.desktop"

ICON_SOURCE="${SCRIPT_DIR}/stemdeck-logo.png"
SYSTEM_ICON="/usr/share/pixmaps/stemdeck-logo.png"

CPU_ARCHIVE="${SCRIPT_DIR}/StemDeck-Linux-x64.tar.gz"
NVIDIA_ARCHIVE="${SCRIPT_DIR}/StemDeck-Linux-x64.NVIDIA.tar.gz"

VERSION="0.8.0-alpha.17"

ARCHIVE=""
VARIANT=""
VARIANT_DISPLAY=""
ARCHIVE_DIR=""
INSTALL_TYPE=""
INSTALL_DIR=""
INSTALLED_EXECUTABLE=""

# ============================================================================
# Utility functions
# ============================================================================

error()
{
    echo
    echo "ERROR: $*" >&2
    echo
    exit 1
}

info()
{
    echo "==> $*"
}

run_privileged()
{
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

confirm()
{
    local prompt="$1"
    local answer

    while true; do
        read -r -p "$prompt [y/n]: " answer

        case "$answer" in
            y|Y|yes|YES)
                return 0
                ;;
            n|N|no|NO)
                return 1
                ;;
            *)
                echo "Please enter y or n."
                ;;
        esac
    done
}

# ============================================================================
# Select archive
# ============================================================================

select_archive()
{
    local cpu_present=false
    local nvidia_present=false

    [[ -f "$CPU_ARCHIVE" ]] && cpu_present=true
    [[ -f "$NVIDIA_ARCHIVE" ]] && nvidia_present=true

    if ! $cpu_present && ! $nvidia_present; then
        error "No StemDeck Linux archive was found.

Expected one or both of:

  StemDeck-Linux-x64.tar.gz
  StemDeck-Linux-x64.NVIDIA.tar.gz"
    fi

    # ------------------------------------------------------------------------
    # Only CPU archive exists.
    # ------------------------------------------------------------------------

    if $cpu_present && ! $nvidia_present; then
        ARCHIVE="$CPU_ARCHIVE"
        VARIANT="CPU"
        VARIANT_DISPLAY="CPU-only"
        ARCHIVE_DIR="StemDeck-Linux-x64"

        info "Only the CPU-only archive was found."
        return
    fi

    # ------------------------------------------------------------------------
    # Only NVIDIA archive exists.
    # ------------------------------------------------------------------------

    if ! $cpu_present && $nvidia_present; then
        ARCHIVE="$NVIDIA_ARCHIVE"
        VARIANT="NVIDIA"
        VARIANT_DISPLAY="NVIDIA"
        ARCHIVE_DIR="StemDeck-Linux-x64.NVIDIA"

        info "Only the NVIDIA archive was found."
        return
    fi

    # ------------------------------------------------------------------------
    # Both archives exist.
    # ------------------------------------------------------------------------

    echo
    echo "Both StemDeck Linux variants were found:"
    echo
    echo "  1) CPU-only"
    echo "     $(basename "$CPU_ARCHIVE")"
    echo
    echo "  2) NVIDIA"
    echo "     $(basename "$NVIDIA_ARCHIVE")"
    echo

    while true; do
        read -r -p "Select version [1-2]: " choice

        case "$choice" in
            1)
                ARCHIVE="$CPU_ARCHIVE"
                VARIANT="CPU"
                VARIANT_DISPLAY="CPU-only"
                ARCHIVE_DIR="StemDeck-Linux-x64"
                break
                ;;

            2)
                ARCHIVE="$NVIDIA_ARCHIVE"
                VARIANT="NVIDIA"
                VARIANT_DISPLAY="NVIDIA"
                ARCHIVE_DIR="StemDeck-Linux-x64.NVIDIA"
                break
                ;;

            *)
                echo "Please enter 1 or 2."
                ;;
        esac
    done
}

# ============================================================================
# Select installation type
# ============================================================================

select_install_location()
{
    local custom_base

    echo
    echo "Select installation type:"
    echo
    echo "  1) Global"
    echo "     /opt/"
    echo
    echo "  2) Local"
    echo "     ${HOME}/.portable/"
    echo
    echo "  3) Custom"
    echo "     Specify an installation directory"
    echo

    while true; do
        read -r -p "Installation type [1-3] (default: 1): " choice

        choice="${choice:-1}"

        case "$choice" in
            1)
                INSTALL_TYPE="Global"
                INSTALL_DIR="/opt/${ARCHIVE_DIR}"
                break
                ;;

            2)
                INSTALL_TYPE="Local"
                INSTALL_DIR="${HOME}/.portable/${ARCHIVE_DIR}"
                break
                ;;

            3)
                echo
                read -r -p "Custom installation directory: " custom_base

                # Remove trailing slashes so that the resulting path
                # has exactly one separator before ARCHIVE_DIR.
                custom_base="${custom_base%/}"

                if [[ -z "$custom_base" ]]; then
                    echo "A directory must be specified."
                    continue
                fi

                # Expand a leading "~" if the user enters one.
                if [[ "$custom_base" == "~" ]]; then
                    custom_base="$HOME"
                elif [[ "$custom_base" == "~/"* ]]; then
                    custom_base="${HOME}/${custom_base#~/}"
                fi

                INSTALL_TYPE="Custom"
                INSTALL_DIR="${custom_base}/${ARCHIVE_DIR}"
                break
                ;;

            *)
                echo "Please enter 1, 2, or 3."
                ;;
        esac
    done
}

# ============================================================================
# Installation
# ============================================================================

install_stemdeck()
{
    local temp_dir
    local source_dir
    local desktop_icon
    local user_icon

    echo
    info "Selected variant: ${VARIANT_DISPLAY}"
    info "Archive: $(basename "$ARCHIVE")"
    info "Version: ${VERSION}"

    # ------------------------------------------------------------------------
    # Check logo.
    # ------------------------------------------------------------------------

    [[ -f "$ICON_SOURCE" ]] ||
        error "StemDeck logo not found:

  ${ICON_SOURCE}

Place stemdeck-logo.png beside this installer."

    # ------------------------------------------------------------------------
    # Check destination.
    # ------------------------------------------------------------------------

    if [[ -e "$INSTALL_DIR" ]]; then
        error "The installation directory already exists:

  ${INSTALL_DIR}

Uninstall the existing StemDeck installation before installing again."
    fi

    # ------------------------------------------------------------------------
    # Create temporary extraction directory.
    # ------------------------------------------------------------------------

    temp_dir="$(mktemp -d)"

    # Always remove temporary extraction directory when the script exits.
    trap 'rm -rf "$temp_dir"' EXIT

    # ------------------------------------------------------------------------
    # Extract.
    # ------------------------------------------------------------------------

    info "Extracting archive..."

    tar -xzf "$ARCHIVE" -C "$temp_dir" ||
        error "Failed to extract archive."

    source_dir="${temp_dir}/${ARCHIVE_DIR}"

    if [[ ! -d "$source_dir" ]]; then
        error "The archive did not contain the expected directory:

  ${ARCHIVE_DIR}

The archive contents may have changed."
    fi

    if [[ ! -f "${source_dir}/StemDeck" ]]; then
        error "The archive did not contain the expected executable:

  ${ARCHIVE_DIR}/StemDeck"
    fi

    info "Found executable:"
    echo "     ${source_dir}/StemDeck"

 # ------------------------------------------------------------------------
# Install application.
# ------------------------------------------------------------------------

info "Installing application to ${INSTALL_DIR}..."

if [[ "$INSTALL_TYPE" == "Global" ]]; then

    run_privileged mkdir -p "$(dirname "$INSTALL_DIR")"

    run_privileged cp -a \
        "$source_dir" \
        "$INSTALL_DIR"

    run_privileged chmod +x \
        "${INSTALL_DIR}/StemDeck"

else

    mkdir -p "$(dirname "$INSTALL_DIR")"

    cp -a \
        "$source_dir" \
        "$INSTALL_DIR"

    chmod +x \
        "${INSTALL_DIR}/StemDeck"

fi

INSTALLED_EXECUTABLE="${INSTALL_DIR}/StemDeck"

    # ------------------------------------------------------------------------
    # Install icon.
    # ------------------------------------------------------------------------

    info "Installing StemDeck icon..."

    if [[ "$INSTALL_TYPE" == "Global" ]]; then

        run_privileged install -Dm644 \
            "$ICON_SOURCE" \
            "$SYSTEM_ICON"

        desktop_icon="stemdeck-logo"

    else

        user_icon="${HOME}/.local/share/icons/stemdeck-logo.png"

        install -Dm644 \
            "$ICON_SOURCE" \
            "$user_icon"

        desktop_icon="$user_icon"

    fi

    # ------------------------------------------------------------------------
    # Create desktop entry.
    # ------------------------------------------------------------------------

    info "Creating desktop entry..."

    mkdir -p "$DESKTOP_DIR"

    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=StemDeck
Comment=Free, local stem separation for music production and practice
Exec=${INSTALLED_EXECUTABLE}
Icon=${desktop_icon}
Categories=Audio;AudioVideo;Multimedia;
Terminal=false
StartupNotify=true
Keywords=music;stems;separation;audio;vocals;drums;bass;
EOF

    # ------------------------------------------------------------------------
    # Create manifest.
    # ------------------------------------------------------------------------

    info "Generating installation manifest..."

    mkdir -p "$CONFIG_DIR"

    {
        echo "# StemDeck installation manifest"
        echo "# Generated by stemdeck-install.sh"
        echo
        echo "Version=${VERSION}"
        echo "Variant=${VARIANT}"
        echo "VariantDisplay=${VARIANT_DISPLAY}"
        echo "InstallType=${INSTALL_TYPE}"
        echo "InstallLocation=${INSTALL_DIR}"
        echo "Executable=${INSTALLED_EXECUTABLE}"
        echo "DesktopFile=${DESKTOP_FILE}"

        if [[ "$INSTALL_TYPE" == "Global" ]]; then
            echo "Icon=${SYSTEM_ICON}"
        else
            echo "Icon=${user_icon}"
        fi

        echo
        echo "FILES_BEGIN"

        find "$INSTALL_DIR" -type f -print | sort

        echo "FILES_END"

    } > "$MANIFEST"

    # ------------------------------------------------------------------------
    # Finished.
    # ------------------------------------------------------------------------

    echo
    echo "StemDeck installation complete."
    echo
    echo "Version:     ${VERSION}"
    echo "Variant:     ${VARIANT_DISPLAY}"
    echo "Install:     ${INSTALL_DIR}"
    echo "Executable:  ${INSTALLED_EXECUTABLE}"
    echo "Desktop:     ${DESKTOP_FILE}"
    echo "Manifest:    ${MANIFEST}"
    echo

    exit 0
}

# ============================================================================
# Read value from manifest
# ============================================================================

manifest_value()
{
    local key="$1"

    grep -E "^${key}=" "$MANIFEST" |
        head -n 1 |
        cut -d= -f2-
}

version_is_newer()
{
    local new_version="$1"
    local old_version="$2"

    [[ "$new_version" != "$old_version" ]] &&
        [[ "$(printf '%s\n' "$old_version" "$new_version" | sort -V | tail -n 1)" == "$new_version" ]]
}

select_installed_archive()
{
    local installed_variant

    installed_variant="$(manifest_value "Variant")"

    case "$installed_variant" in
        CPU)
            ARCHIVE="$CPU_ARCHIVE"
            VARIANT="CPU"
            VARIANT_DISPLAY="CPU-only"
            ARCHIVE_DIR="StemDeck-Linux-x64"
            ;;

        NVIDIA)
            ARCHIVE="$NVIDIA_ARCHIVE"
            VARIANT="NVIDIA"
            VARIANT_DISPLAY="NVIDIA"
            ARCHIVE_DIR="StemDeck-Linux-x64.NVIDIA"
            ;;

        *)
            error "The existing StemDeck manifest contains an invalid variant:

  ${installed_variant:-<missing>}

The installation manifest may be corrupted."
            ;;
    esac

    if [[ ! -f "$ARCHIVE" ]]; then
        error "The installed StemDeck variant is ${VARIANT_DISPLAY}, but its archive was not found beside this installer.

Expected:

  $(basename "$ARCHIVE")

To change between CPU-only and NVIDIA versions, uninstall the existing installation first and then run the installer again with the desired archive."
    fi

    info "Existing architecture: ${VARIANT_DISPLAY}"
    info "Using archive: $(basename "$ARCHIVE")"
}

# ============================================================================
# Uninstallation
# ============================================================================

uninstall_stemdeck()
{
    local version
    local variant
    local install_type
    local install_location
    local executable
    local desktop_file
    local icon

    version="$(manifest_value "Version")"
    variant="$(manifest_value "VariantDisplay")"
    install_type="$(manifest_value "InstallType")"
    install_location="$(manifest_value "InstallLocation")"
    executable="$(manifest_value "Executable")"
    desktop_file="$(manifest_value "DesktopFile")"
    icon="$(manifest_value "Icon")"

    echo
    echo "Existing StemDeck installation found."
    echo
    echo "Version:     ${version:-unknown}"
    echo "Variant:     ${variant:-unknown}"
    echo "Install:     ${install_location:-unknown}"
    echo

    if ! confirm "Uninstall StemDeck?"; then
        echo
        echo "Uninstallation cancelled."
        echo
        exit 0
    fi

    echo
    info "Removing StemDeck application..."

    # ------------------------------------------------------------------------
    # Remove application directory.
    # ------------------------------------------------------------------------

    if [[ -n "$install_location" && -e "$install_location" ]]; then

        if [[ "$install_type" == "Global" ]]; then
            run_privileged rm -rf "$install_location"
        else
            rm -rf "$install_location"
        fi

    fi

    # ------------------------------------------------------------------------
    # Remove desktop entry.
    # ------------------------------------------------------------------------

    if [[ -n "$desktop_file" && -f "$desktop_file" ]]; then
        rm -f "$desktop_file"
    fi

    # ------------------------------------------------------------------------
    # Remove icon.
    # ------------------------------------------------------------------------

    if [[ -n "$icon" && -f "$icon" ]]; then

        if [[ "$install_type" == "Global" ]]; then
            run_privileged rm -f "$icon"
        else
            rm -f "$icon"
        fi

    fi

    # ------------------------------------------------------------------------
    # Remove manifest.
    # ------------------------------------------------------------------------

    rm -f "$MANIFEST"

    # ------------------------------------------------------------------------
    # Remove empty directories.
    # ------------------------------------------------------------------------

    rmdir "$CONFIG_DIR" 2>/dev/null || true
    rmdir "$DESKTOP_DIR" 2>/dev/null || true
    rmdir "${HOME}/.local/share/icons" 2>/dev/null || true

    echo
    echo "StemDeck has been uninstalled."
    echo

    exit 0
}

# ============================================================================
# Upgrading
# ============================================================================

upgrade_stemdeck()
{
    local old_install_type
    local old_install_location
    local old_desktop_file
    local old_icon

    old_install_type="$(manifest_value "InstallType")"
    old_install_location="$(manifest_value "InstallLocation")"
    old_desktop_file="$(manifest_value "DesktopFile")"
    old_icon="$(manifest_value "Icon")"

    echo
    info "Upgrading StemDeck..."
    echo
    echo "Architecture: ${VARIANT_DISPLAY}"
    echo "Version:      ${VERSION}"
    echo

    # Preserve the existing installation type.
    INSTALL_TYPE="$old_install_type"

case "$INSTALL_TYPE" in
    Global)
        INSTALL_DIR="/opt/${ARCHIVE_DIR}"
        ;;

    Local)
        INSTALL_DIR="${HOME}/.portable/${ARCHIVE_DIR}"
        ;;

    Custom)
        INSTALL_DIR="$old_install_location"
        ;;

    *)
        error "The existing StemDeck manifest contains an invalid installation type:

  ${INSTALL_TYPE:-<missing>}"
        ;;
esac

    # ------------------------------------------------------------------------
    # Remove old application.
    # ------------------------------------------------------------------------

    if [[ -n "$old_install_location" && -e "$old_install_location" ]]; then

        info "Removing previous application..."

        if [[ "$old_install_type" == "Global" ]]; then
            run_privileged rm -rf "$old_install_location"
        else
            rm -rf "$old_install_location"
        fi

    fi

    # ------------------------------------------------------------------------
    # Remove old desktop entry.
    # ------------------------------------------------------------------------

    if [[ -n "$old_desktop_file" && -f "$old_desktop_file" ]]; then
        rm -f "$old_desktop_file"
    fi

    # ------------------------------------------------------------------------
    # Remove old icon.
    # ------------------------------------------------------------------------

    if [[ -n "$old_icon" && -f "$old_icon" ]]; then

        if [[ "$old_install_type" == "Global" ]]; then
            run_privileged rm -f "$old_icon"
        else
            rm -f "$old_icon"
        fi

    fi

    # ------------------------------------------------------------------------
    # Remove old manifest.
    # ------------------------------------------------------------------------

    rm -f "$MANIFEST"

    # ------------------------------------------------------------------------
    # Remove empty directories.
    # ------------------------------------------------------------------------

    rmdir "$CONFIG_DIR" 2>/dev/null || true
    rmdir "$DESKTOP_DIR" 2>/dev/null || true
    rmdir "${HOME}/.local/share/icons" 2>/dev/null || true

    # ------------------------------------------------------------------------
    # Install new version.
    # ------------------------------------------------------------------------

    install_stemdeck
}

# ============================================================================
# Main
# ============================================================================

echo
echo "========================================"
echo "        StemDeck Linux Installer"
echo "========================================"
echo

# ============================================================================
# Existing installation
#
# Check for the manifest BEFORE asking which architecture to install.
# An existing installation determines the architecture automatically.
# ============================================================================

if [[ -f "$MANIFEST" ]]; then

    INSTALLED_VERSION="$(manifest_value "Version")"
    INSTALLED_VARIANT="$(manifest_value "VariantDisplay")"
    INSTALLED_TYPE="$(manifest_value "InstallType")"
    INSTALLED_LOCATION="$(manifest_value "InstallLocation")"

    # Select the same architecture as the existing installation.
    select_installed_archive

    echo
    echo "Existing StemDeck installation found."
    echo
    echo "Installed version: ${INSTALLED_VERSION:-unknown}"
    echo "Available version: ${VERSION}"
    echo "Architecture:      ${INSTALLED_VARIANT:-unknown}"
    echo "Installation type: ${INSTALLED_TYPE:-unknown}"
    echo "Installation:      ${INSTALLED_LOCATION:-unknown}"
    echo

    # ------------------------------------------------------------------------
    # Newer version available.
    # ------------------------------------------------------------------------

    if [[ -n "${INSTALLED_VERSION}" ]] &&
       version_is_newer "$VERSION" "$INSTALLED_VERSION"; then

        echo "A newer version of StemDeck is available."
        echo
        echo "  1) Upgrade"
        echo "  2) Uninstall"
        echo "  3) Cancel"
        echo

        while true; do
            read -r -p "Select an option [1-3]: " choice

            case "$choice" in
                1)
                    upgrade_stemdeck
                    ;;

                2)
                    uninstall_stemdeck
                    ;;

                3)
                    echo
                    echo "Operation cancelled."
                    echo
                    exit 0
                    ;;

                *)
                    echo "Please enter 1, 2, or 3."
                    ;;
            esac
        done

    # ------------------------------------------------------------------------
    # Same version or installed version is newer.
    # ------------------------------------------------------------------------

    else

        echo "No newer version is available."
        echo
        echo "  1) Uninstall"
        echo "  2) Cancel"
        echo

        while true; do
            read -r -p "Select an option [1-2]: " choice

            case "$choice" in
                1)
                    uninstall_stemdeck
                    ;;

                2)
                    echo
                    echo "Operation cancelled."
                    echo
                    exit 0
                    ;;

                *)
                    echo "Please enter 1 or 2."
                    ;;
            esac
        done

    fi

fi

# ============================================================================
# New installation
#
# No manifest exists, so this is a genuinely new installation and the user
# gets to select CPU-only or NVIDIA.
# ============================================================================

select_archive
select_install_location
install_stemdeck

exit 0
