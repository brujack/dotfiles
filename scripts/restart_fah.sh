#!/usr/bin/env bash

sudo systemctl stop FAHClient

sleep 2

for pid in $(pgrep fah)
do
  sudo kill -9 "${pid}"
done

sleep 2

sudo systemctl start FAHClient
