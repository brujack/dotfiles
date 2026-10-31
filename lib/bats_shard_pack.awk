# CPU-weighted LPT packing for scripts/bats-shard.sh. ARGV is the weights table,
# then every .bats path; run as
#   LC_ALL=C awk -F'\t' -v idx=<shard> -v n=<count> -v hc=<handicap> -f this-file table files...
# Prints shard <idx>'s paths in path order; on error prints "bats-shard: ..." on
# stderr and exits 2 with nothing on stdout. Lives in its own file because a
# multi-line single-quoted program inside a .sh counts as uncoverable lines in bash-coverage.
  function fail(msg) { printf "bats-shard: %s\n", msg > "/dev/stderr"; failed = 1; exit 2 }
  BEGIN {
    wfile = ARGV[1]
    for (i = 2; i < ARGC; i++) { nfiles++; path[nfiles] = ARGV[i]; known[ARGV[i]] = 1 }
  }
  FILENAME == wfile {
    if ($0 ~ /^#/) next
    if ($0 ~ /\r$/) fail(wfile ": line " FNR " is a CRLF line")
    if (NF != 2 || $2 !~ /^[0-9]+(\.[0-9]+)?$/) fail(wfile ": malformed line " FNR ": " $0)
    if ($1 in row) fail(wfile ": duplicate row at line " FNR ": " $1)
    row[$1] = $2 + 0
    next
  }
  /^@test/ { tests[FILENAME]++ }
  END {
    if (failed) exit 2
    live = 0; cpu = 0; cnt = 0
    for (r in row) {
      if (r in known) { live++; cpu += row[r]; cnt += tests[r] + 0 }
      else dead[++nd] = r
    }
    # Name dead rows in path order so stderr is deterministic.
    for (a = 2; a <= nd; a++) { v = dead[a]; b = a - 1; while (b >= 1 && dead[b] > v) { dead[b + 1] = dead[b]; b-- } dead[b + 1] = v }
    for (a = 1; a <= nd; a++) printf "bats-shard: dead row: %s\n", dead[a] > "/dev/stderr"
    if (live == 0) fail(wfile ": no live rows")
    if (cnt == 0) fail(wfile ": live rows hold no @test lines")
    per = cpu / cnt
    for (i = 1; i <= nfiles; i++) w[i] = (path[i] in row) ? row[path[i]] : (tests[path[i]] + 0) * per
    # Order: heaviest first, ties by path ascending (insertion sort; ~90 files).
    for (i = 1; i <= nfiles; i++) ord[i] = i
    for (i = 2; i <= nfiles; i++) {
      v = ord[i]; j = i - 1
      while (j >= 1 && (w[ord[j]] < w[v] || (w[ord[j]] == w[v] && path[ord[j]] > path[v]))) { ord[j + 1] = ord[j]; j-- }
      ord[j + 1] = v
    }
    for (s = 1; s <= n; s++) load[s] = 0
    load[1] = hc + 0
    for (i = 1; i <= nfiles; i++) {
      f = ord[i]; best = 1
      for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
      load[best] += w[f]; owner[f] = best
    }
    for (i = 1; i <= nfiles; i++) if (owner[i] == idx + 0) print path[i]
  }
