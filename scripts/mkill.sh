#!/bin/sh

pattern=$1

for pid in $(ps -ef | grep -i "${pattern}" | grep -v grep | awk '{print $2}')
do
  sudo kill -9 "${pid}"
done
