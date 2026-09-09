#!/bin/bash
# Base image DE: openbox (linuxserver baseimage-selkies default).
ulimit -c 0
exec openbox-session
