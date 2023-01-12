#!/usr/bin/env bash

SDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
julia --code-coverage=user $SDIR/allany_server.jl &