# Reads apt output on stdin; prints "host<TAB>token" once per distinct host named
# on a signature-failure line. Called by _apt_stale_signer_hosts in lib/linux_shared.sh
# with -v prefixes=... -v tokens=... ("|"-joined). Lives in its own file because a
# multi-line single-quoted program inside a .sh counts as uncoverable lines in bash-coverage.
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
  if (found == "") next
  rest = $0
  # authority = text after the scheme up to the first / quote or space
  while (match(rest, /https?:\/\/[^\/\047 ]+/)) {
    url = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    sub(/^https?:\/\//, "", url)
    sub(/^[^@]*@/, "", url)
    sub(/:[0-9]*$/, "", url)
    url = tolower(url)
    if (!(url in seen)) { seen[url] = 1; printf "%s\t%s\n", url, found }
  }
}
