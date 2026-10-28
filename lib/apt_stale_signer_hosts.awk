# Reads apt output on stdin; prints "host<TAB>token" once per distinct host named
# on a signature-failure line. Called by _apt_scan_failed_hosts in lib/linux_shared.sh
# with -v prefixes=... -v tokens=... ("|"-joined). Lives in its own file because a
# multi-line single-quoted program inside a .sh counts as uncoverable lines in bash-coverage.
# With -v mode=fetch it reads the other failure apt update exits 0 on: a "Failed to
# fetch" line carrying no signer token (an unreachable host, a 404), and prints
# "host<TAB>reason". host is the source URL's host or, when the source has no
# http(s) URL (file:, cdrom:), the source token up to its first space. A signer
# failure also prints a "Failed to fetch" line, so the token test keeps each
# source in exactly one of the two reports.
BEGIN {
  np = split(prefixes, pre, "|")
  nt = split(tokens, tok, "|")
}
{
  sub(/\r$/, "")
  ok = 0
  for (i = 1; i <= np; i++) {
    if (substr($0, 1, length(pre[i])) == pre[i]) { ok = 1; break }
  }
  if (!ok) next
  found = ""
  for (i = 1; i <= nt; i++) {
    if (index($0, tok[i]) > 0) { found = tok[i]; break }
  }
  rest = $0
  if (mode == "fetch") {
    if (found != "" || index($0, "Failed to fetch ") == 0) next
    found = $0
    sub(/^.*Failed to fetch [^ ]+ */, "", found)
    if (found == "") found = "no reason given"
    # Only the source URL names the host: the reason can carry another URL (a redirect target).
    rest = substr($0, index($0, "Failed to fetch ") + 16)
    sub(/ .*/, "", rest)
  } else if (found == "") next
  # authority = text after the scheme up to the first / quote or space
  got = 0
  while (match(rest, /https?:\/\/[^\/\047 ]+/)) {
    got = 1
    url = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    sub(/^https?:\/\//, "", url)
    sub(/^[^@]*@/, "", url)
    sub(/:[0-9]*$/, "", url)
    url = tolower(url)
    if (!(url in seen)) { seen[url] = 1; printf "%s\t%s\n", url, found }
  }
  # A fetch failure on a source with no http(s) URL (file:, cdrom:) still names it,
  # by the whole source string, so the row never reads OK for it.
  if (mode == "fetch" && !got && rest != "" && !(rest in seen)) { seen[rest] = 1; printf "%s\t%s\n", rest, found }
}
