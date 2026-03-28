#!/usr/bin/env bash

# Check if a directory path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 directory_path directory_path_to_ignore with no trailing slashes"
  exit 1
fi

dir_path="$1"
dir_ignore="$2"

total_lines=0

while read -r file
do
  lines=$(wc -l <"$file")
  total_lines=$((total_lines + lines))
  echo "$file has $lines lines"
done < <(find "$dir_path" -type d -path "$dir_ignore" -prune -o -type f -print)

echo "Total lines: $total_lines"
