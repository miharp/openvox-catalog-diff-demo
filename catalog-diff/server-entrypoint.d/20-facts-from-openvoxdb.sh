#!/bin/bash
# Make OpenVoxDB the server's facts terminus, as a package install connected
# to OpenVoxDB has it. The image only sets storeconfigs, which leaves OpenVoxDB
# as a facts cache. The certless catalog API then finds no trusted facts for a
# node and overwrites the node's stored trusted fact.

set -e

route_file="$(puppet config print route_file --section server)"

if [ -e "$route_file" ]; then
  echo "$route_file already exists, leaving it alone"
  exit 0
fi

cat > "$route_file" <<'YAML'
---
server:
  facts:
    terminus: puppetdb
    cache: yaml
YAML

echo "Wrote $route_file"
