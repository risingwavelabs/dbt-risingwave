#!/usr/bin/env bash
# Minimal provisioning to run the e2e GitHub Action jobs locally:
# install the adapter, write a dbt profile per e2e project, wait for RisingWave.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "==> Installing dbt-risingwave (editable)"
pip install -e .

echo "==> Writing ~/.dbt/profiles.yml"
mkdir -p "$HOME/.dbt"
: > "$HOME/.dbt/profiles.yml"
# Profiles for the two projects we care about (each project uses a profile named
# after its `profile:` key).
for proj in indexes zero_downtime; do
	name="$(sed -n 's/^profile:[[:space:]]*//p' "tests/e2e/${proj}/dbt_project.yml")"
	cat >> "$HOME/.dbt/profiles.yml" <<EOF
${name}:
  target: dev
  outputs:
    dev:
      type: risingwave
      host: risingwave
      user: root
      pass: ""
      dbname: dev
      port: 4566
      schema: public
EOF
done

echo "==> Waiting for RisingWave"
timeout 120 bash -c 'until (echo > /dev/tcp/risingwave/4566) 2>/dev/null; do sleep 1; done' \
	&& echo "==> Ready." \
	|| echo "==> WARNING: RisingWave not reachable yet; check the 'risingwave' service." >&2
