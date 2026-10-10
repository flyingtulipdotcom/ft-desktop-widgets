#!/usr/bin/env bash
# Runs every offline test: xbar plugin, Rainmeter Lua and lint. Needs node and lua5.1 (luac5.1).
set -eu
cd "$(dirname "$0")"
node xbar/test/run.js | tail -1
lua5.1 rainmeter/test/run.lua | tail -1
node rainmeter/test/lint.js
