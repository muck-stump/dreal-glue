#!/usr/bin/env bash
#
# summary.sh — the human-readable correctness view, extractable from this repo
# alone: one row per cell (pass/fail from runs/completeness.<cell>.txt), every
# failing target named below, and the A-vs-B verdict. Prints to stdout and
# writes runs/SUMMARY.md. Needs no container/build state — it reads the
# committed artifacts only.
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=cells.env
source "$ROOT/harness/cells.env"

env_label() { # what each cell's environment *is* (presentation lives here)
  case "$1" in
    A|B) echo "ubuntu 22.04 reference container (podman)" ;;
    C)   echo "this Mac, host cell (macOS $(sw_vers -productVersion 2>/dev/null || echo '?'), Apple Silicon)" ;;
    D)   echo "ubuntu 24.04 container (podman)" ;;
    E)   echo "fedora 43 container (podman)" ;;
    *)   echo "?" ;;
  esac
}
code_label() { # short commit + role
  local short
  short=$(cell_commit "$1" | cut -c1-7)
  case "$1" in
    A)      echo "\`$short\` — original code" ;;
    B|D|E)  echo "\`$short\` — modernized" ;;
    C)      echo "\`$short\` — modernized (submodule pin)" ;;
    *)      echo "\`$short\`" ;;
  esac
}

{
  echo "# dreal4 cell status"
  echo
  echo "Generated: \`$(date -u +%FT%TZ)\` by \`harness/summary.sh\` — do not edit;"
  echo "regenerated after every run (\`harness/run-all.sh\`). Evidence lives in git."
  echo
  echo "| cell | code | environment | result |"
  echo "|---|---|---|---|"
  for c in $CELLS; do
    comp="$ROOT/runs/completeness.$c.txt"
    if [ ! -f "$comp" ]; then
      echo "| $c | $(code_label $c) | $(env_label $c) | not run yet |"
      continue
    fi
    line=$(head -1 "$comp")
    total=$(printf '%s' "$line" | sed -n 's/.*Executed \([0-9][0-9]*\) out of \([0-9][0-9]*\).*/\2/p')
    total=${total:-?}
    if [ -f "$ROOT/runs/failed.$c.txt" ]; then
      nfail=$(awk 'END{print NR+0}' "$ROOT/runs/failed.$c.txt")
    else
      nfail=0
    fi
    # Bazel's own accounting is authoritative: targets that failed to *build*
    # while the build was breaking often never print a per-target status row,
    # so failed.txt under-lists them (seen live: a broken build recorded 5
    # labels for 323 failures — completeness.txt caught it, first summary
    # draft didn't).
    nb=nlocal=0
    if [[ $line =~ \ ([0-9]+)\ fails?\ to\ build ]]; then nb=${BASH_REMATCH[1]}; fi
    if [[ $line =~ and\ ([0-9]+)\ fails?\ locally ]]; then nlocal=${BASH_REMATCH[1]}; fi
    ntotal=$((nb + nlocal))
    case "$line" in
      *LOADING\ ERRORS*|*BUILD\ DID\ NOT\ COMPLETE*) broken=1 ;;
      *) broken=0 ;;
    esac
    if [ "$broken" = 1 ]; then
      state="**BROKEN RUN ✗** ($ntotal failing by bazel's count, $nfail listed — see completeness + log)"
    elif [ "$ntotal" -gt 0 ] && [ "$nfail" -ne "$ntotal" ]; then
      state="**suspect ✗** (bazel says $ntotal failing, failed.txt lists $nfail — see log)"
    elif [ "$nfail" -eq 0 ]; then
      state="**$total/$total PASS ✓**"
    else
      state="**${nfail}/$total failing ✗**"
    fi
    echo "| $c | $(code_label $c) | $(env_label $c) | $state |"
  done
  echo

  # The question this repo exists for: same env, two commits — identical or not?
  if [ -f "$ROOT/runs/failed.A.txt" ] && [ -f "$ROOT/runs/failed.B.txt" ]; then
    if [ -z "$(comm -3 "$ROOT/runs/failed.A.txt" "$ROOT/runs/failed.B.txt")" ]; then
      echo "**A vs B (the code question): identical** — both cells have the same"
      echo "(empty) failing set; \`comm -3 runs/failed.A.txt runs/failed.B.txt\` is empty."
      echo
    else
      diffl=$(comm -3 "$ROOT/runs/failed.A.txt" "$ROOT/runs/failed.B.txt" | sed 's/^[[:space:]]*//' | sort -u)
      nonflake=
      # timer_test is a pre-registered known flake (report.md): it is recorded
      # in failed.txt when it flakes, but a divergence *consisting only* of it
      # is the expected category, not a code-vs-code finding — say so instead
      # of leading with an alarming DIFFERS headline.
      while IFS= read -r t; do
        [ -z "$t" ] && continue
        case "$t" in //dreal/util:timer_test) ;; *) nonflake="$nonflake $t" ;; esac
      done <<< "$diffl"
      if [ -z "$nonflake" ]; then
        echo "**A vs B: identical apart from the known \`timer_test\` timing flake** (recorded in"
        echo "failed lists when it flakes; pre-registered category — see report.md). No"
        echo "code-vs-code divergence."
        echo
      else
        echo "**A vs B (the code question): DIFFERS** — \`comm -3\` of the failing lists:"
        echo '```'
        comm -3 "$ROOT/runs/failed.A.txt" "$ROOT/runs/failed.B.txt"
        echo '```'
        echo "(left column = A only, right column = B only)"
        echo
      fi
    fi
  fi

  # Details: name every failure, by cell (this is the "where do we see fails").
  any=0
  for c in $CELLS; do
    f="$ROOT/runs/failed.$c.txt"
    [ -s "$f" ] || continue
    any=1
    echo "## Cell $c — $(wc -l < "$f") failing target(s)"
    echo '```'
    cat "$f"
    echo '```'
    if [ -f "$ROOT/runs/flaky.$c.txt" ] && [ -s "$ROOT/runs/flaky.$c.txt" ]; then
      echo "flaky-then-passed in $c: $(tr '\n' ' ' < "$ROOT/runs/flaky.$c.txt")"
      echo
    fi
    echo
  done
  [ "$any" -eq 1 ] || echo "No failing targets anywhere."
  echo
  echo "Raw artifacts per cell: \`runs/failed.<cell>.txt\`, \`runs/completeness.<cell>.txt\`,"
  echo "\`runs/env-manifest.<cell>.txt\`, \`runs/bazel-test.<cell>.log\`."
} > "$ROOT/runs/SUMMARY.md"

cat "$ROOT/runs/SUMMARY.md"
