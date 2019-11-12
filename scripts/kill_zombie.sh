#!/bin/sh

pattern="<defunct>"
processes=`ps -ef | grep $pattern | grep -v grep | awk '{print $3 }'`

kill -9 ${processes}
