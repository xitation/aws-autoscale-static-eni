#!/bin/sh
sudo iptables -nL -v --line-numbers -t mangle
sudo iptables -nL -v --line-numbers -t nat
