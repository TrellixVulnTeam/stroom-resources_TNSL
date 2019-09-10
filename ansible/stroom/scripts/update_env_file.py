from utils import get_inventory, get_service_fqdn, remove_line_from_file
import sys

def prepend_line(path, line):
    file = open(path, "r+")
    content = file.read()
    file.seek(0,0)
    file.write(line.rstrip('\r\n') + '\n' + content)


def main():
    path_to_stack = sys.argv[1]
    env_file_path = f'{path_to_stack}/latest/config/stroom_core.env'
    inventory = get_inventory()
    fqdn = get_service_fqdn(inventory)
    export_text = 'export HOST_IP'
    host_ip_export_line = f"{export_text}={fqdn}"
    remove_line_from_file(env_file_path, f"{export_text}=")
    prepend_line(env_file_path, host_ip_export_line)


main()
