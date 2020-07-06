#!/bin/sh

sudo /etc/init.d/FAHClient stop

for pid in $(ps -ef | grep -i fah | grep -v grep | awk '{print $2}')
do
  sudo kill -9 "${pid}"
done

sudo /etc/init.d/FAHClient start
