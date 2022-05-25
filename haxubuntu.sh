#!/bin/bash

sed 's/us.archive.ubuntu.com/archive.ubuntu.com/' -i /etc/apt/sources.list
apt-get update
