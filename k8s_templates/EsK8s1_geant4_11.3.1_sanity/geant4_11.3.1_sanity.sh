#!/bin/bash
set -euo pipefail

echo "[K8S-TEST] Start: $(date)"
echo "[K8S-TEST] Node:  $(hostname)"
echo "[K8S-TEST] User:  $(whoami)"
echo "[K8S-TEST] Pwd:   $(pwd)"
echo

echo "[K8S-TEST] Environment snippet:"
echo "  G4INSTALL=${G4INSTALL:-undefined}"
echo "  G4VERSION=${G4VERSION:-undefined}"
echo "  ROOTSYS=${ROOTSYS:-undefined}"
echo

echo "[K8S-TEST] Checking Geant4 / ROOT / Python..."
command -v geant4-config  >/dev/null 2>&1 && geant4-config --version || echo "geant4-config NOT found"
command -v root-config    >/dev/null 2>&1 && root-config   --version || echo "root-config NOT found"
command -v python3        >/dev/null 2>&1 && python3        --version || echo "python3 NOT found"
echo

python3 - << 'EOF'
import sys, platform
print("Python:", sys.version.split()[0])
print("Platform:", platform.platform())
EOF

echo
echo "[K8S-TEST] Done: $(date)"
