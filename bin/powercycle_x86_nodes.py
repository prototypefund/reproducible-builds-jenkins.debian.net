#!/usr/bin/python3

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

from profitbricks.client import ProfitBricksService
import json
import os
import sys

# expects node numbers or 'jenkins' as params...
nodes=[]
for argument in sys.argv:   
    try:
        node=int(argument)
        name=('build'+str(node))
        nodes.append(name)
    except:
        try:
            if argument=='jenkins':
                nodes.append(argument)
        except:
            pass

#for node in nodes:
#    print (node)

client = ProfitBricksService(
    username=os.getenv('IONOS_USERNAME'),
    password=os.getenv('IONOS_PASSWORD'))

response = client.list_datacenters(0)
#print (json.dumps(response, indent=4))

for item in response['items']:
    datacenter=item['id']
    #print (datacenter)
    response = client.list_servers(datacenter_id=datacenter)
    #print (json.dumps(response, indent=4))
    for item in response['items']:
        #print (item['id'])
        #print (item['type'])
        for server in nodes:
            if item['type'] == 'server' and item['properties']['name'] == server:
                print ('Rebooting '+item['properties']['name']+' aka '+server) 
                result = client.reboot_server(datacenter, item['id'])
                print (result)
