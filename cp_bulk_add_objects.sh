#!/bin/bash
#This script adds host objects present in addresses.txt file and publishes changes, you need to create the file with each line containing new object 
mgmt_cli login -r true > id.txt
input="addresses.txt"
while IFS= read -r line
do
  mgmt_cli add host name "$line" ip-address "$line" groups groupname -s id.txt
done < "$input"
mgmt_cli publish -s id.txt
