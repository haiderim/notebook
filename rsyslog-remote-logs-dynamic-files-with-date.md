# A simple remote syslog server config 

*Tested on Alma Linux 8.3*

The following config receives logs and writes them to folders for each host by date and at the same time prevents remote logs from being written to */var/log/messages.*

_/etc/rsyslog.d/100-remote.conf_
```###Begin Config###

#Receive logs and write them in a folder based on IP from which they are received, new file will be created each day
$template RemoteHost,"/var/log/remote/%fromhost-ip%/%$year%-%$month%-%$day%.log"

#Create ruleset
$RuleSet remote
*.* ?RemoteHost

#Enable Syslog listener and bind the ruleset to it
module(load="imudp")
input(type="imudp" port="514" RuleSet="remote")

#Prevent remote logs from being written to /var/log/messages
if $fromhost-ip != '127.0.0.1' then stop

###End Config###```
