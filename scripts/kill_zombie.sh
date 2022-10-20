#!/bin/sh

pattern="<defunct>"
processes=$(pgrep "${pattern}")

kill -9 "${processes}"
