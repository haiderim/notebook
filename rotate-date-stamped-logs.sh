#!/bin/bash
find /var/log/remote/* -mtime +7 -delete;
find /var/log/remote/* -maxdepth 1 -type f -name "*.log" -mtime +1 -exec gzip -9 {} \;