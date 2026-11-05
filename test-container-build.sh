#!/bin/bash

# Build the container image and smoke-test kickstart and OEMDRV ISO generation.
# Set RHEL_SOURCE_ISO to also build and verify a modified boot ISO.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly IMAGE_NAME="create-ks-iso-test"

CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
CONTAINER_ENGINE_SUDO="${CONTAINER_ENGINE_SUDO:-false}"
RHEL_SOURCE_ISO="${RHEL_SOURCE_ISO:-}"
TEST_OUTPUT_BASE="${TEST_OUTPUT_BASE:-${HOME:-}}"
WRITEPASSWDS="${WRITEPASSWDS:-false}"

if [[ -z "$CONTAINER_ENGINE" ]]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  else
    echo "Error: Docker or Podman is required." >&2
    exit 1
  fi
elif ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
  echo "Error: container engine '$CONTAINER_ENGINE' was not found." >&2
  exit 1
fi

if [[ "$CONTAINER_ENGINE_SUDO" != true && "$CONTAINER_ENGINE_SUDO" != false ]]; then
  echo "Error: CONTAINER_ENGINE_SUDO must be true or false." >&2
  exit 1
fi

if [[ "$WRITEPASSWDS" != true && "$WRITEPASSWDS" != false ]]; then
  echo "Error: WRITEPASSWDS must be true or false." >&2
  exit 1
fi

run_engine() {
  if [[ "$CONTAINER_ENGINE_SUDO" == true ]]; then
    sudo -n "$CONTAINER_ENGINE" "$@"
  else
    "$CONTAINER_ENGINE" "$@"
  fi
}

if [[ "$CONTAINER_ENGINE_SUDO" == true ]]; then
  if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true; then
    echo "Error: non-interactive sudo is required when CONTAINER_ENGINE_SUDO=true." >&2
    exit 1
  fi
fi

if [[ -n "$RHEL_SOURCE_ISO" ]]; then
  if [[ ! -f "$RHEL_SOURCE_ISO" ]]; then
    echo "Error: source ISO not found: $RHEL_SOURCE_ISO" >&2
    exit 1
  fi
  if [[ -z "$TEST_OUTPUT_BASE" || ! -d "$TEST_OUTPUT_BASE" ]]; then
    echo "Error: TEST_OUTPUT_BASE must be an existing directory on disk-backed storage." >&2
    exit 1
  fi

  output_fs=$(stat -f -c %T -- "$TEST_OUTPUT_BASE")
  case "$output_fs" in
    tmpfs|ramfs)
      echo "Error: TEST_OUTPUT_BASE is on $output_fs; choose a disk-backed directory." >&2
      exit 1
      ;;
  esac

  source_iso=$(realpath -- "$RHEL_SOURCE_ISO")
  source_iso_name=$(basename -- "$source_iso")
  source_iso_dir=$(dirname -- "$source_iso")
  source_iso_bytes=$(stat -c %s -- "$source_iso")
  output_free_kb=$(df -Pk -- "$TEST_OUTPUT_BASE" | awk 'NR == 2 {print $4}')
  root_free_kb=$(df -Pk / | awk 'NR == 2 {print $4}')
  output_required_kb=$(((source_iso_bytes + 1073741824 + 1023) / 1024))
  root_required_kb=$(((source_iso_bytes * 3 + 1023) / 1024))

  if ((output_free_kb < output_required_kb)); then
    echo "Error: TEST_OUTPUT_BASE needs at least source ISO size plus 1 GiB free." >&2
    exit 1
  fi
  if ((root_free_kb < root_required_kb)); then
    echo "Error: filesystem / needs at least three times the source ISO size free for container work files." >&2
    exit 1
  fi

  if [[ "$CONTAINER_ENGINE" == podman ]]; then
    rootless=$(run_engine info --format '{{.Host.Security.Rootless}}')
    if [[ "$rootless" == true ]]; then
      echo "Error: boot ISO builds require rootful Podman for the ISO mount. Set CONTAINER_ENGINE_SUDO=true." >&2
      exit 1
    fi
  fi

  output_dir=$(mktemp -d "$TEST_OUTPUT_BASE/create-ks-iso-test.XXXXXX")
  printf 'Full ISO test output: %s\n' "$output_dir"
fi

run_engine build --tag "$IMAGE_NAME" "$SCRIPT_DIR"

run_engine run --rm \
  --env OSTYPE=RHEL \
  --env MAJOROSVERSION=9 \
  --env KSVALIDATOR_CHECKS=true \
  --env KS_HOSTNAME=iso-build-test \
  --entrypoint bash "$IMAGE_NAME" \
  -euo pipefail -c '
    /create-ks-iso/create-ks-iso.sh
    test -s /create-ks-iso/result/ks/ks.cfg
  '

"$CONTAINER_ENGINE" run --rm \
  --env OSTYPE=RHEL \
  --env MAJOROSVERSION=9 \
  --env KSVALIDATOR_CHECKS=true \
  --env KS_HOSTNAME=iso-build-test \
  --env CREATEOEMDRVISO=true \
  --entrypoint bash "$IMAGE_NAME" \
  -euo pipefail -c '
    /create-ks-iso/create-ks-iso.sh
    test -s /create-ks-iso/result/ks/ks.cfg
    test -s /create-ks-iso/result/iso/OEMDRV.iso
    isoinfo -i /create-ks-iso/result/iso/OEMDRV.iso -f |
      grep -Ei "^/KS\\.CFG(;[0-9]+)?$" >/dev/null
  '

if [[ -n "$RHEL_SOURCE_ISO" ]]; then
  run_engine run --rm --privileged \
      --volume "$source_iso_dir:/create-ks-iso/isosrc:ro,Z" \
      --volume "$output_dir:/create-ks-iso/result:Z" \
      --env SUDO_UID="$(id -u)" \
      --env SUDO_GID="$(id -g)" \
      --env OEMSRCISO="$source_iso_name" \
      --env CREATEBOOTISO=true \
      --env ENABLEFIPS=true \
      --env KSINBOOTISO=true \
      --env WRITEPASSWDS="$WRITEPASSWDS" \
      --env KSVALIDATOR_CHECKS=true \
      "$IMAGE_NAME"

  boot_iso="$output_dir/iso/FIPS-Embedded-kickstart-$source_iso_name"
  if [[ ! -s "$boot_iso" ]]; then
      echo "Error: expected boot ISO was not created: $boot_iso" >&2
      exit 1
  fi

  run_engine run --rm \
      --volume "$output_dir:/test:ro,Z" \
      --entrypoint bash "$IMAGE_NAME" \
      -euo pipefail -c '
        checkisomd5 "/test/iso/$1"
        isoinfo -i "/test/iso/$1" -f |
          grep -Ei "^/KS\\.CFG(;[0-9]+)?$" >/dev/null
      ' bash "$(basename -- "$boot_iso")"

  printf 'Modified boot ISO and embedded ks.cfg verified: %s\n' "$boot_iso"
fi

echo "Container build, kickstart validation, and OEMDRV ISO smoke tests passed."
