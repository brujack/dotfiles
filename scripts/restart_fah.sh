#!/bin/sh

sudo /etc/init.d/FAHClient stop

sleep 2

for pid in $(ps -ef | grep -i fah | grep -v grep | awk '{print $2}')
do
  sudo kill -9 "${pid}"
done

sleep 2

sudo /etc/init.d/FAHClient start
