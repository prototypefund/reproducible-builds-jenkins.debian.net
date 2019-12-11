#!/usr/bin/python3

# Copyright 2019 Holger Levsen <holger@layer-acht.org>
# released under the GPLv2

import os
import sys
import json
import logging

from profitbricks.client import ProfitBricksService


log = logging.getLogger(__name__)
_ch = logging.StreamHandler()
_ch.setFormatter(logging.Formatter(("%(levelname)s: %(message)s")))
log.addHandler(_ch)
log.setLevel(logging.INFO)
# log.setLevel(logging.DEBUG)

# expects node numbers or 'jenkins' as params...
nodes = []
for argument in sys.argv[1:]:
    try:
        node = int(argument)
    except ValueError:
        # argument wasn't an integer
        if argument == "jenkins":
            nodes.append(argument)
        else:
            log.error("Unrecognized node: %s", argument)
            sys.exit(1)
    else:
        name = "build" + str(node)
        nodes.append(name)

log.debug("Acting on nodes: %s", nodes)

client = ProfitBricksService(
    username=os.getenv("IONOS_USERNAME"), password=os.getenv("IONOS_PASSWORD")
)

response = client.list_datacenters(0)
log.debug(json.dumps(response, indent=4))

for item in response["items"]:
    datacenter = item["id"]
    log.debug(datacenter)
    response = client.list_servers(datacenter_id=datacenter)
    log.debug(json.dumps(response, indent=4))
    for item in response["items"]:
        log.debug(item['id'])
        log.debug(item['type'])
        for server in nodes:
            if item["type"] == "server" and item["properties"]["name"] == server:
                log.info("Rebooting " + item["properties"]["name"] + " aka " + server)
                result = client.reboot_server(datacenter, item["id"])
                log.info(result)
