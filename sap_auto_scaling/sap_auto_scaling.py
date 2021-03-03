"""
The script use to auto scaling AAS instance. 
Author: Alibaba Cloud, SAP Product & Solution Team
Refer: https://github.com/a30001784/azure_tags/blob/2879c1fdd4e4ed411a9b06fdc3bb15d39264388d/ansible/roles/app-post/scripts/adapt_logon_groups.py
"""

import argparse, json
from pyrfc import Connection


class ServerGroup:
    connection: Connection = None
    setup_list: list = None

    def __init__(self, host, sysnr, client, user, passwd):
        self.set_connection(host, sysnr, client, user, passwd)

    def set_connection(self, host, sysnr, client, user, passwd):
        self.connection = Connection(ashost=host, sysnr=sysnr, client=client, user=user, passwd=passwd)

    def call(self, func_name: str, *args, **kargs):
        return self.connection.call(func_name, *args, **kargs)

    def set_up(self, group_type):
        res = self.call('SMLG_GET_SETUP', GROUPTYPE=group_type)
        self.setup_list = res.get('SETUP', [])

    def smlg_modify(self, group_type, classname, applserver, modificatn):
        dst = {
            'CLASSNAME': classname,
            'APPLSERVER': applserver,
            'MODIFICATN': modificatn,
        }
        self.call("SMLG_MODIFY", GROUPTYPE=group_type, MODIFICATIONS=[dst])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update SAP ABAP Groups")
    parser.add_argument("-i", "--hostname", type=str, required=True, help="Application server hostname")
    parser.add_argument("-u", "--username", type=str, required=True, help="Application server username")
    parser.add_argument("-p", "--password", type=str, required=True, help="Application server password")
    parser.add_argument("-a", "--applserver", type=str, required=True, help="Instance name")
    parser.add_argument("-c", "--client", type=str, required=True, help="Application client")
    parser.add_argument("-n", "--number", type=str, required=True, help="Instance number")
    parser.add_argument("-C", "--classname", type=str, required=False, help="Group name, default 'SPACE'")
    args = parser.parse_args()

    if args.classname is None or args.classname == 'SPACE':
        group_type = 'S'
        classname = '  390'
    else:
        group_type = ''
        classname = args.classname

    group = ServerGroup(host=args.hostname, sysnr=args.number, client=args.client, user=args.username, passwd=args.password)
    group.set_up(group_type) 
    # I: update D: delete
    group.smlg_modify(group_type, classname, args.applserver, 'I')