import os
import sys
import json
import shutil
import psutil

#!/usr/bin/env python3

def format_size(bytes_num):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_num < 1024.0:
            return f"{bytes_num:.0f}{unit}"
        bytes_num /= 1024.0
    return f"{bytes_num:.0f}PB"

def get_biggest_disk_usage():
    partitions = [p for p in psutil.disk_partitions(all=False) if os.path.ismount(p.mountpoint)]
    biggest = max(partitions, key=lambda p: shutil.disk_usage(p.mountpoint).total)
    usage = shutil.disk_usage(biggest.mountpoint)
    used = usage.used
    total = usage.total
    percent = used / total * 100
    return {
        "used": used,
        "total": total,
        "percent": percent,
        "mountpoint": biggest.mountpoint
    }

def get_ram_usage():
    vm = psutil.virtual_memory()
    used = vm.total - vm.available
    total = vm.total
    percent = used / total * 100
    return {
        "used": used,
        "total": total,
        "percent": percent
    }

def main():
    as_json = '--json' in sys.argv
    disk = get_biggest_disk_usage()
    ram = get_ram_usage()

    disk_str = f"{format_size(disk['used'])} / {format_size(disk['total'])} ({disk['percent']:.0f}%)"
    ram_str = f"{format_size(ram['used'])} / {format_size(ram['total'])} ({ram['percent']:.0f}%)"

    if as_json:
        print(json.dumps({
            "disk": disk_str,
            "ram": ram_str
        }))
    else:
        print(f"{'Disk':<8} {disk_str}")
        print(f"{'RAM':<8} {ram_str}")

if __name__ == "__main__":
    main()