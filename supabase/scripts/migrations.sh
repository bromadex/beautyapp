#!/usr/bin/env bash
# Migration-history helpers for the Supabase GitHub workflows.
#
#   migrations.sh guard
#       Fails unless the database's migration history already knows our first
#       migration. Stops `supabase db push` from re-running every migration
#       against a database whose history was never set up.
#
#   migrations.sh baseline [--pending "<version> ..."] [--apply]
#       One-time setup. Migrations used to be applied by hand (SQL editor and
#       MCP), so the history table is empty or holds versions that don't match
#       our file names. This marks every local migration as applied except the
#       --pending ones, and removes history rows that have no local file.
#       Without --apply it only prints what it would do.
#
# Needs SUPABASE_DB_URL (percent-encoded Postgres URL), psql and the supabase CLI.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
: "${SUPABASE_DB_URL:?Set SUPABASE_DB_URL (Supabase dashboard > Connect > Session pooler)}"
supabase=${SUPABASE_BIN:-supabase}

local_versions() {
  ls supabase/migrations | sed -n 's/^\([0-9]\{14\}\)_.*\.sql$/\1/p' | sort
}

remote_versions() {
  local has
  has=$(psql "$SUPABASE_DB_URL" -Atc \
    "select to_regclass('supabase_migrations.schema_migrations') is not null")
  if [ "$has" = "t" ]; then
    psql "$SUPABASE_DB_URL" -Atc \
      "select version from supabase_migrations.schema_migrations order by 1"
  fi
}

# Words in $1 that aren't in $2 (both newline-separated, sorted).
minus() { comm -23 <(printf '%s\n' "$1" | sed '/^$/d' | sort) <(printf '%s\n' "$2" | sed '/^$/d' | sort); }

cmd_guard() {
  local first remote
  first=$(local_versions | head -1)
  remote=$(remote_versions)
  if ! grep -qx "$first" <<<"$remote"; then
    echo "::error::Migration history isn't set up: $first is not recorded in the database." >&2
    echo "Run the 'Supabase baseline' workflow once (see supabase/README.md), then re-run this." >&2
    exit 1
  fi
  echo "Migration history OK ($(wc -l <<<"$remote" | tr -d ' ') recorded)."
}

cmd_baseline() {
  local pending="" apply=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --pending) pending=$(tr ', ' '\n\n' <<<"$2"); shift 2 ;;
      --apply) apply=true; shift ;;
      *) echo "Unknown option $1" >&2; exit 2 ;;
    esac
  done

  local locals remote stray to_mark unknown
  locals=$(local_versions)
  remote=$(remote_versions)

  unknown=$(minus "$pending" "$locals")
  if [ -n "$unknown" ]; then
    echo "::error::--pending names versions with no migration file: $unknown" >&2
    exit 2
  fi

  stray=$(minus "$remote" "$locals")
  to_mark=$(minus "$(minus "$locals" "$pending")" "$remote")

  echo "History rows with no local file (will be removed): ${stray:-none}" | tr '\n' ' '; echo
  echo "Local migrations to mark applied: $(wc -w <<<"$to_mark" | tr -d ' ')"
  echo "Left for 'db push' to run: ${pending:-none}" | tr '\n' ' '; echo

  if ! $apply; then
    echo "Dry run. Re-run with --apply to change the history table."
    return
  fi
  # Only the history table changes; no migration SQL runs here.
  if [ -n "$stray" ]; then
    # shellcheck disable=SC2086
    "$supabase" migration repair --db-url "$SUPABASE_DB_URL" --status reverted $stray
  fi
  if [ -n "$to_mark" ]; then
    # shellcheck disable=SC2086
    "$supabase" migration repair --db-url "$SUPABASE_DB_URL" --status applied $to_mark
  fi
  echo "Baseline done."
}

case "${1:-}" in
  guard) shift; cmd_guard "$@" ;;
  baseline) shift; cmd_baseline "$@" ;;
  *) echo "usage: $0 guard | baseline [--pending \"<version> ...\"] [--apply]" >&2; exit 2 ;;
esac
