#!/usr/bin/env bash

sudo /etc/init.d/FAHClient stop

sleep 2

for pid in $(pgrep fah)
do
  sudo kill -9 "${pid}"
done

sleep 2

sudo /etc/init.d/FAHClient start
