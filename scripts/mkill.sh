#!/bin/sh

pattern=$1
processes=`ps ax | grep $pattern | grep -v grep | awk '{print $1 }'`

kill -9 ${processes}
