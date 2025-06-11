#!/usr/bin/env bash
# Fetches the list of allowed globals for luacheck.
# The file is stored separately to keep the repository lightweight.
# Run this script whenever you need to update the globals list.

URL="https://raw.githubusercontent.com/luarocks/lua-global-variables/master/globals.lua"
DEST="luacheck_globals.lua"

curl -fsSL "$URL" -o "$DEST"
