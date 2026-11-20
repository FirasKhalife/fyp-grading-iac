#!/usr/bin/env bash
# assay-compose: docker compose for the production stack, from anywhere (sudo assay-compose ps, logs -f edge, ...).
PROG=assay-compose
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh
compose "$@"
