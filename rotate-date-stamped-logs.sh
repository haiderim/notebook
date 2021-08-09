#!/bin/bash
#Logrotate doesn't play nice with files that have timestamps in filenames, so needed to use this script for log rotation. You can place this inside /etc/cron.daily/ or /etc/cron.weekly/. We also need to use absolute path of commands as find doesn't work without that from cron.
find /var/log/remote/* -mtime +7 -delete;
find /var/log/remote/* -maxdepth 1 -type f -name "*.log" -mtime +1 -exec gzip -9 {} \;
