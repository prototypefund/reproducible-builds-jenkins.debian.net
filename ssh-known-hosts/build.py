#! /usr/bin/python3

import sys
import yaml

with open('list.yml') as f:
    data = yaml.load(f)


class Host:
    def __init__(self, d):
        self.hostname = d['hostname']
        self.ip = d['ip']
        self.keys = d['keys']


for host in data:
    try:
        h = Host(host)
    except KeyError as e:
        print('Missing required key "{}"'.format(e), file=sys.stderr)
        sys.exit(1)

    for key in h.keys:
        print('{},{} {}'.format(h.hostname, h.ip, key))
