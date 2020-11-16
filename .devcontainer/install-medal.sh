#!/bin/sh

if [ $# -eq 1 ]; then
    download_str="download/$1"
else
    download_str=latest/download
fi

curl -SL https://github.com/tom-tan/medal/releases/${download_str}/medal-linux-x86_64.tar.gz \
    | tar xC /usr/bin
