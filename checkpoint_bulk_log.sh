#!/bin/bash
#The script changes logging settings in Firewall Network policy layer to enable firewall sessions and disable connection logging, you'd need to publish the changes manually. Publish wasn't included as you'd ideally want to review the changes and then publish them manually. The script was tested on R80.40 and R81.10 management servers.
mgmt_cli login -r true > id.txt
echo "Enter total number of rules in policy"
read limit
echo "Enter policy layer name"
read layername
for ((i=1;i<=limit;i++)); do
mgmt_cli set access-rule rule-number $i track.per-session true track.per-connection false track.enable-firewall-session true track.type "Detailed Log" layer "$layername" -s id.txt
done
