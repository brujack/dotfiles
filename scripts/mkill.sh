#!/usr/bin/env bash

pattern=$1

for pid in $(pgrep "${pattern}")
do
  sudo kill -9 "${pid}"
done
