#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${plantbridge_project_dir}/scripts/bootstrap-nifi-laboratory.sh" --run-once
