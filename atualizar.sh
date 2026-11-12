#!/bin/bash
set -eu
RAIZ="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec bash "$RAIZ/scripts/atualizar.sh" "$@"
