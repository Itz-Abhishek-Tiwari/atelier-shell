#!/usr/bin/env python3
"""System monitor feed for the Atelier shell.

Prints one JSON object per second (until killed): CPU / memory / network / temperatures / GPU,
the busiest apps and battery details. Only reads /proc and /sys, so it never wakes a sleeping
NVIDIA GPU (nvidia-smi is queried only while the card is already awake).

usage: sysmon.py            stream, one line per second
       sysmon.py once       a single sample (CPU % over 0.4 s)
"""
import glob
import json
import os
import subprocess
import sys
import time

HZ = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
PAGE = os.sysconf("SC_PAGE_SIZE")


def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def cpu_times():
    out = []
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu"):
            p = line.split()
            v = [int(x) for x in p[1:9]]
            out.append((p[0], sum(v), v[3] + v[4]))        # name, total, idle (idle + iowait)
    return out


def meminfo():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024
    total = m.get("MemTotal", 0)
    avail = m.get("MemAvailable", 0)
    return {"total": total, "used": total - avail, "swapTotal": m.get("SwapTotal", 0),
            "swapUsed": m.get("SwapTotal", 0) - m.get("SwapFree", 0)}


def net_bytes():
    rx = tx = 0
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name == "lo" or name.startswith(("veth", "docker", "br-", "virbr")):
            continue
        f = rest.split()
        rx += int(f[0])
        tx += int(f[8])
    return rx, tx


def temps():
    cpu = gpu = nvme = None
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        name = read(h + "/name")
        t = read(h + "/temp1_input")
        if not t.isdigit():
            continue
        c = int(t) / 1000
        if name in ("k10temp", "coretemp", "zenpower") and cpu is None:
            cpu = c
        elif name == "amdgpu" and gpu is None:
            gpu = c
        elif name == "nvme" and nvme is None:
            nvme = c
    return {"cpu": cpu, "gpu": gpu, "nvme": nvme}


def gpus():
    out = []
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]")):
        dev = card + "/device"
        vendor = read(dev + "/vendor")
        busy = read(dev + "/gpu_busy_percent")
        if vendor == "0x1002" and busy.isdigit():
            used, total = read(dev + "/mem_info_vram_used"), read(dev + "/mem_info_vram_total")
            out.append({"name": "AMD iGPU" if total and int(total) < 3 << 30 else "AMD GPU",
                        "busy": int(busy),
                        "mem": int(used) if used.isdigit() else 0,
                        "memTotal": int(total) if total.isdigit() else 0})
        elif vendor == "0x10de":
            # only ask while the card is already awake: nvidia-smi would power it up
            if read(dev + "/power/runtime_status") != "active":
                out.append({"name": "NVIDIA", "busy": 0, "asleep": True})
                continue
            try:
                r = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
                                    "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=2)
                u, mu, mt = [x.strip() for x in r.stdout.strip().split(",")]
                out.append({"name": "NVIDIA", "busy": int(u), "mem": int(mu) << 20, "memTotal": int(mt) << 20})
            except Exception:
                out.append({"name": "NVIDIA", "busy": 0})
    return out


def battery():
    b = "/sys/class/power_supply/BAT0"
    if not os.path.isdir(b):
        for p in glob.glob("/sys/class/power_supply/BAT*"):
            b = p
            break
        else:
            return None
    num = lambda n: int(read(b + "/" + n, "0") or 0)
    full, design, now = num("energy_full"), num("energy_full_design"), num("energy_now")
    if not full:                                         # charge-based (µAh) instead of energy-based
        full, design, now = num("charge_full"), num("charge_full_design"), num("charge_now")
    power = num("power_now") / 1e6
    ct = read(b + "/charge_types")
    cur = ct[ct.find("[") + 1:ct.find("]")] if "[" in ct else ct
    return {"status": read(b + "/status"), "pct": num("capacity"), "watts": round(power, 1),
            "health": round(100 * full / design) if design else None, "cycles": num("cycle_count"),
            "fullWh": round(full / 1e6, 1), "designWh": round(design / 1e6, 1),
            "limitable": "Long_Life" in ct, "limited": cur == "Long_Life",
            "hours": round(now / 1e6 / power, 2) if power > 0.5 and read(b + "/status") == "Discharging" else None}


def proc_stats():
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                s = f.read()
            rp = s.rindex(")")
            name = s[s.index("(") + 1:rp]
            r = s[rp + 2:].split()
            ticks = int(r[11]) + int(r[12])               # utime + stime
            rss = int(r[21]) * PAGE
            out[int(d)] = (name, ticks, rss)
        except (OSError, ValueError, IndexError):
            pass
    return out


def display_name(pid, comm):
    # the executable's real name beats thread names like "Isolated Web Co" or "GeckoMain"
    try:
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        if exe and not exe.startswith("python") and exe != "node":
            return exe.replace(" (deleted)", "")
    except OSError:
        pass
    return comm


class Sampler:
    def __init__(self):
        self.cpu = cpu_times()
        self.net = net_bytes()
        self.procs = proc_stats()
        self.t = time.monotonic()
        self.slow = 0
        self.cache = {}

    def sample(self):
        now = time.monotonic()
        dt = max(0.05, now - self.t)
        cpu = cpu_times()
        cores = []
        for (n, t1, i1), (_, t0, i0) in zip(cpu, self.cpu):
            cores.append(round(100 * (1 - (i1 - i0) / (t1 - t0)), 1) if t1 > t0 else 0)
        net = net_bytes()
        down, up = (net[0] - self.net[0]) / dt, (net[1] - self.net[1]) / dt
        procs = proc_stats()
        apps = {}
        for pid, (name, ticks, rss) in procs.items():
            old = self.procs.get(pid)
            pcpu = 100 * ((ticks - old[1]) / HZ) / dt if old else 0
            a = apps.setdefault(display_name(pid, name), {"name": "", "cpu": 0.0, "mem": 0, "n": 0, "pid": pid, "top": -1})
            a["cpu"] += pcpu
            a["mem"] += rss
            a["n"] += 1
            if pcpu > a["top"]:
                a["top"], a["pid"] = pcpu, pid
        for k, a in apps.items():
            a["name"] = k
            a["cpu"] = round(a["cpu"], 1)
        rows = list(apps.values())
        byc = sorted(rows, key=lambda a: -a["cpu"])[:8]
        bym = sorted(rows, key=lambda a: -a["mem"])[:8]
        # slow things (temps, GPU, battery) every 2 s
        if self.slow % 2 == 0:
            self.cache = {"temps": temps(), "gpus": gpus(), "battery": battery()}
        self.slow += 1
        self.cpu, self.net, self.procs, self.t = cpu, net, procs, now
        up_s = float(read("/proc/uptime", "0 0").split()[0])
        return {"cpu": cores[0] if cores else 0, "cores": cores[1:], "ncpu": NCPU, "mem": meminfo(),
                "down": down, "up": up, "load": os.getloadavg(), "uptime": up_s,
                "byCpu": [{k: v for k, v in a.items() if k != "top"} for a in byc],
                "byMem": [{k: v for k, v in a.items() if k != "top"} for a in bym], **self.cache}


def main():
    s = Sampler()
    if len(sys.argv) > 1 and sys.argv[1] == "once":
        time.sleep(0.4)
        print(json.dumps(s.sample()))
        return
    while True:
        time.sleep(1)
        try:
            print(json.dumps(s.sample()), flush=True)
        except BrokenPipeError:
            return


if __name__ == "__main__":
    main()
