#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <exec_rel_path> <macro_rel_path>"
  echo "Example: $0 exampleB5 run1.mac"
  exit 1
fi

EXEC_REL="$1"
MACRO_REL="$2"

echo "[RUN] Start: $(date)"
echo "[RUN] Host:  $(hostname)"
echo "[RUN] User:  $(whoami)"
echo "[RUN] Pwd:   $(pwd)"
echo "[RUN] Exec:  ${EXEC_REL}"
echo "[RUN] Macro: ${MACRO_REL}"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[RUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[RUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

EXEC_PATH="./${EXEC_REL}"
MACRO_PATH="./${MACRO_REL}"

if [[ ! -x "${EXEC_PATH}" ]]; then
  echo "[RUN] ERROR: executable not found or not executable: ${EXEC_PATH}"
  exit 1
fi
if [[ ! -f "${MACRO_PATH}" ]]; then
  echo "[RUN] ERROR: macro not found: ${MACRO_PATH}"
  exit 1
fi

echo "[RUN] Launching: ${EXEC_PATH} ${MACRO_PATH}"
"${EXEC_PATH}" "${MACRO_PATH}"

echo
echo "[RUN] Done: $(date)"
