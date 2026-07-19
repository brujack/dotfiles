#!/usr/bin/env bash

# html2ascii: a simple html to ascii convertor and tokenizer
# usage:      html2ascii [-h|--help] [file]
# note:       the html tags (like <p>) will be removed from the file
#             and the html character entities (like &aring;) will be
#             replaced by appropriate characters. The result will be
#             tokenized and the tokens will be shown on standard output.
# 960312 erik.tjong@ling.uu.se

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: html2ascii.sh [file]

Strips HTML tags, replaces a small set of HTML character entities with
their UTF-8 characters, and tokenizes the result (one token per line).
Reads from the given file, or from stdin when no file is given.
USAGE
  exit 0
fi

# If no input file specified, read from standard input; otherwise read
# from the given file.
if [[ -z "${1:-}" ]]; then
  cat
else
  cat "$1"
fi |
  # Remove every substring starting with < and ending with > (html tags).
  sed -e 's/<[^>]*>//g' -e 's/<[^>]*$//g' -e 's/^[^>]*>//g' |
  # Replace a small set of HTML character entities with their UTF-8
  # characters.
  sed -e 's/&aring;/å/g' -e 's/&Aring;/Å/g' -e 's/&auml;/ä/g' \
    -e 's/&Auml;/Ä/g' -e 's/&ouml;/ö/g' -e 's/&Ouml;/Ö/g' |
  # Tokenize: one word per line.
  tr ' ' '\012' |
  # Strip a trailing sentence-ending punctuation mark from each token.
  sed 's/[\.?,:;!]$//g' |
  # Strip stray quote characters: both literal " and `, plus a leading or
  # trailing ' (but not one embedded mid-word, e.g. "John's").
  sed -e "s/\"//" -e "s/\`//" -e "s/ \' //" -e "s/\' //"
