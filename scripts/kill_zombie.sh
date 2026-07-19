#!/usr/bin/env bash

pattern="<defunct>"

for pid in $(pgrep "${pattern}"); do
  kill -9 "${pid}"
done
