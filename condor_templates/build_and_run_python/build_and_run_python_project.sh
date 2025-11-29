#!/bin/bash
set -euo pipefail

# Parametri configurabili (via environment o editando il file)
SRC_DIR="${SRC_DIR:-source}"           # cartella sorgenti (relativa alla initialdir)
BUILD_DIR="${BUILD_DIR:-build}"        # cartella di build
PYTHON_SCRIPT="${PYTHON_SCRIPT:-source/run_batch.py}"  # script Python da lanciare (relativo alla initialdir)
EXEC_NAME="${EXEC_NAME:-<EXEC_NAME>}"  # nome del binario prodotto dalla build (es. CsI-WLS)

echo "[BUILD+RUN] Start: $(date)"
echo "[BUILD+RUN] Host:  $(hostname)"
echo "[BUILD+RUN] User:  $(whoami)"
echo "[BUILD+RUN] Pwd:   $(pwd)"
echo "[BUILD+RUN] SRC_DIR       = ${SRC_DIR}"
echo "[BUILD+RUN] BUILD_DIR     = ${BUILD_DIR}"
echo "[BUILD+RUN] PYTHON_SCRIPT = ${PYTHON_SCRIPT}"
echo "[BUILD+RUN] EXEC_NAME     = ${EXEC_NAME}"
echo

if [[ -f /opt/geant4/bin/geant4.sh ]]; then
  echo "[BUILD+RUN] Sourcing Geant4..."
  source /opt/geant4/bin/geant4.sh
fi
if [[ -f /opt/root/bin/thisroot.sh ]]; then
  echo "[BUILD+RUN] Sourcing ROOT..."
  source /opt/root/bin/thisroot.sh
fi

# --- BUILD ---

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "[BUILD+RUN] Now in build dir: $(pwd)"

if [[ -x "${EXEC_NAME}" ]]; then
  echo "[BUILD+RUN] ${EXEC_NAME} already built, skipping cmake/cmake --build."
else
  echo "[BUILD+RUN] Configuring with CMake..."
  cmake "../${SRC_DIR}"

  echo "[BUILD+RUN] Building ${EXEC_NAME}..."
  cmake --build . -- -j"$(nproc)"
fi

if [[ ! -x "${EXEC_NAME}" ]]; then
  echo "[BUILD+RUN] ERROR: binary ${EXEC_NAME} not found after build."
  exit 1
fi

# --- RUN via Python ---

cd ..

echo
echo "[BUILD+RUN] Running Python script: ${PYTHON_SCRIPT}"
python3 "${PYTHON_SCRIPT}"

echo
echo "[BUILD+RUN] Done at $(date)"
