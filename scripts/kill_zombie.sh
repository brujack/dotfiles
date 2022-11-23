#!/usr/bin/env bash

pattern="<defunct>"
processes=$(pgrep "${pattern}")

kill -9 "${processes}"
