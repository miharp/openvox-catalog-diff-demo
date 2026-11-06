#!/usr/bin/env bash
# Diff the catalogs of every demo node between two git refs.
#
#   catalog-diff/run.sh [BASE_REF] [HEAD_REF]
#
# BASE_REF is deployed as the `production` environment and HEAD_REF as
# `change`. Set KEEP=1 to leave the stack running afterwards.

set -euo pipefail

base_ref="${1:-production}"
head_ref="${2:-HEAD}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
work="$here/.work"
puppet=/opt/puppetlabs/bin/puppet
agents=(web01 web02 db01)

compose() { docker compose --project-directory "$here" "$@"; }
step() { printf '\n==> %s\n' "$*"; }

cleanup() {
  if [[ "${KEEP:-0}" != 1 ]]; then
    step 'Tearing down'
    compose down --volumes --remove-orphans
  fi
}
trap cleanup EXIT

step "Deploying $base_ref as production and $head_ref as change"
rm -rf "$work"
mkdir -p "$work/environments/production" "$work/environments/change" "$work/report"
git -C "$repo" archive "$base_ref" | tar -x -C "$work/environments/production"
git -C "$repo" archive "$head_ref" | tar -x -C "$work/environments/change"

step 'Starting the server, OpenVoxDB, and agents'
compose up --detach --wait

step 'Running each agent once in noop mode, so OpenVoxDB has its facts'
for agent in "${agents[@]}"; do
  echo "--- $agent"
  compose exec -T "$agent" "$puppet" agent --test --noop --server puppet --certname "$agent"
done

step 'Waiting for OpenVoxDB to store facts and a catalog for each agent'
stored_nodes() {
  compose exec -T openvoxserver bash -c '
    ssl=/etc/puppetlabs/puppet/ssl
    curl -sS -G https://openvoxdb:8081/pdb/query/v4 \
      --cacert "$ssl/certs/ca.pem" --cert "$ssl/certs/puppet.pem" --key "$ssl/private_keys/puppet.pem" \
      --data-urlencode "query=nodes[count()] { catalog_timestamp is not null and facts_timestamp is not null }"
  '
}
for attempt in {1..30}; do
  stored="$(stored_nodes)"
  [[ "$stored" == *"\"count\":${#agents[@]}"* ]] && break
  if (( attempt == 30 )); then
    echo "OpenVoxDB has not stored every agent: $stored" >&2
    exit 1
  fi
  sleep 2
done
echo "OpenVoxDB has facts and a catalog for ${#agents[@]} nodes"

step 'Preparing the Catalog Diff node'
compose exec -T catalog-diff bash -euo pipefail -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get -qq update
  apt-get -qq install -y openvoxdb-termini >/dev/null
  printf '[main]\nserver_urls = https://openvoxdb:8081\n' > /etc/puppetlabs/puppet/puppetdb.conf
  $puppet ssl bootstrap --server puppet --certname catalog-diff
  $puppet module install puppet-catalog_diff
"

step "Comparing each node's catalog compiled from production and from change"
# Catalog Diff's own output is long, so it goes to a file and the report is
# summarized instead. It is shown if the command itself fails.
if ! compose exec -T catalog-diff "$puppet" catalog diff \
  puppet:8140/production puppet:8140/change \
  --certname catalog-diff \
  --filter_old_env \
  --certless \
  --show_resource_diff \
  --content_diff \
  --color false \
  --output_report /report/report.json > "$work/report/diff.txt" 2>&1; then
  cat "$work/report/diff.txt"
  exit 1
fi

echo "Full output and JSON report: ${work#"$repo"/}/report/"

# Tear down first so the summary is the last thing on screen.
trap - EXIT
cleanup

echo
"$here/summary.py" --text "$work/report/report.json"
