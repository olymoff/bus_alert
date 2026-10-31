#!/bin/bash
cd "$(dirname "$0")"
while true; do
  ruby -e 'STDOUT.sync = true; load "run_bot.rb"' >> bot.log 2>&1
  sleep 5
done
