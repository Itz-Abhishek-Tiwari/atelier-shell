#!/usr/bin/env python3
"""Hardware summary for Settings → About, as JSON.

    hardware.py          {"device": {...}, "groups": [{"title", "rows": [[label, value, detail?], ...]}]}

Reads only /sys, /proc and hyprctl. PCI names come from sysfs ids + hwdata's pci.ids instead of
lspci: lspci reads each device's config space, which wakes a runtime-suspended NVIDIA dGPU.
Static facts are cached in ~/.cache/atelier/hardware.json (refreshed after a reboot or kernel
change); battery, memory use and displays are read fresh every time.
"""
import json
import os
import re
import subprocess
from pathlib import Path

CACHE = Path.home() / ".cache/atelier/hardware.json"
SYS = Path("/sys")


def read(p, default=""):
    try:
        return Path(p).read_text(errors="replace").strip()
    except OSError:
        return default


def gb(nbytes, digits=0):
    v = nbytes / 1e9
    return f"{v:.{digits}f} GB" if v < 1000 else f"{v / 1000:.1f} TB"


# ---- PCI names (pci.ids) ------------------------------------------------------------
def pci_names(wanted):
    """{(vendor, device): (vendor name, device name)} for the wanted ids."""
    out, vendor, vname = {}, None, None
    want_v = {v for v, _ in wanted}
    for path in ("/usr/share/hwdata/pci.ids", "/usr/share/misc/pci.ids"):
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith("C "):
                        break
                    if not line.strip() or line.startswith("#"):
                        continue
                    if not line.startswith("\t"):
                        vendor, _, vname = line.strip().partition("  ")
                    elif not line.startswith("\t\t") and vendor in want_v:
                        dev, _, dname = line.strip().partition("  ")
                        if (vendor, dev) in wanted:
                            out[(vendor, dev)] = (vname, dname)
            return out
        except OSError:
            continue
    return out


def short_vendor(v):
    for k, s in (("NVIDIA", "NVIDIA"), ("Advanced Micro Devices", "AMD"), ("Intel", "Intel"),
                 ("Qualcomm", "Qualcomm"), ("Realtek", "Realtek"), ("MEDIATEK", "MediaTek"),
                 ("Broadcom", "Broadcom")):
        if k.lower() in v.lower():
            return s
    return v.split(",")[0].split(" Inc")[0]


def clean_device(name, laptop=False):
    # "TU117M [GeForce GTX 1650 Mobile / Max-Q]" -> "GeForce GTX 1650 Mobile"
    m = re.search(r"\[(.+)\]", name)
    name = m.group(1) if m else name
    if " / " in name:                 # pci.ids lists variants: keep one (the mobile one on laptops)
        head, *alts = [a.strip() for a in name.split(" / ")]
        mobile = next((a for a in [head] + alts if "Mobile" in a), None)
        name = mobile if laptop and mobile else head
        if laptop and mobile and not mobile.startswith(head.split()[0]) and " " not in mobile:
            name = f"{head} {mobile}"
    name = re.sub(r"\b(PCI Express|Network Adapter|Controller|Wireless|Adapter)\b", "", name)
    return re.sub(r"\s{2,}", " ", name).strip()


def pci_devices():
    devs = []
    for d in sorted((SYS / "bus/pci/devices").glob("*")):
        cls = read(d / "class")
        v, dv = read(d / "vendor")[2:].lower(), read(d / "device")[2:].lower()
        devs.append({"path": d, "class": cls, "id": (v, dv)})
    names = pci_names({x["id"] for x in devs})
    for x in devs:
        vn, dn = names.get(x["id"], ("", ""))
        x["vendor"], x["name"] = vn, dn
    return devs


def serial_number():
    """The DMI serial is root-only in /sys; systemd-hostnamed hands it to the active session.
    Never interactively: where polkit wants a password for it, the prompt window made the
    Settings drawer close (it closes on any new window), and reopening About asked again in a loop."""
    s = read(SYS / "class/dmi/id/product_serial")
    if not s:
        try:
            r = subprocess.run(["busctl", "--allow-interactive-authorization=no", "call",
                                "org.freedesktop.hostname1", "/org/freedesktop/hostname1",
                                "org.freedesktop.hostname1", "GetHardwareSerial"],
                               capture_output=True, text=True, timeout=10)
            m = re.match(r's "(.*)"', r.stdout.strip())
            s = m.group(1) if m else ""
        except Exception:
            s = ""
    return "" if s.lower() in ("", "none", "default string", "to be filled by o.e.m.", "0123456789") else s


def ram_modules():
    """Installed modules + free slots, from udev's DMI memory properties (no root needed)."""
    try:
        out = subprocess.run(["udevadm", "info", "/sys/class/dmi/id"], capture_output=True, text=True,
                             timeout=3).stdout
    except Exception:
        return ""
    p = dict(re.findall(r"^E: (MEMORY_[A-Z0-9_]+)=(.*)$", out, re.M))
    slots = int(p.get("MEMORY_ARRAY_NUM_DEVICES", "0") or 0)
    mods = []
    for i in range(slots):
        size = p.get(f"MEMORY_DEVICE_{i}_SIZE")
        if not size or p.get(f"MEMORY_DEVICE_{i}_PRESENT") == "0":
            continue
        known = lambda k: (v := p.get(f"MEMORY_DEVICE_{i}_{k}", "")) and v != "Unknown" and v
        typ = known("TYPE") or ""
        speed = known("CONFIGURED_SPEED_MTS") or known("SPEED_MTS")
        bits = [f"{int(size) // 2**30} GB " + (f"{typ}-{speed}" if typ and speed else typ)]
        if known("FORM_FACTOR"):
            bits.append(known("FORM_FACTOR"))
        maker = " ".join(x for x in (known("MANUFACTURER"), known("PART_NUMBER")) if x)
        if maker:
            bits.append(maker)
        mods.append(" ".join(bits[:1]) + (" · " + " · ".join(bits[1:]) if bits[1:] else ""))
    if not mods:
        return ""
    txt = " + ".join(mods)
    if slots:
        txt += f" · {len(mods)} of {slots} slots used"
        cap = p.get("MEMORY_ARRAY_MAX_CAPACITY", "")
        if cap.isdigit():
            txt += f" (max {int(cap) // 2**30} GB)"
    return txt


# ---- static facts --------------------------------------------------------------------
def static_info():
    dmi = SYS / "class/dmi/id"
    vendor = read(dmi / "sys_vendor").title() if read(dmi / "sys_vendor").isupper() else read(dmi / "sys_vendor")
    family = read(dmi / "product_version")         # Lenovo puts the marketing name here
    product = read(dmi / "product_name")
    if not family or family.lower() in ("none", "to be filled by o.e.m.", "default string"):
        family, product = product, ""
    chassis = {"8": "Laptop", "9": "Laptop", "10": "Laptop", "14": "Laptop", "31": "Convertible", "32": "Laptop",
               "3": "Desktop", "4": "Desktop", "6": "Desktop", "7": "Desktop", "13": "All-in-one",
               "30": "Tablet", "35": "Mini PC"}.get(read(dmi / "chassis_type"), "Computer")

    cpu = {}
    for line in read("/proc/cpuinfo").splitlines():
        k, _, v = line.partition(":")
        k, v = k.strip(), v.strip()
        if k in ("model name", "cpu cores", "siblings", "cache size") and k not in cpu:
            cpu[k] = v
    cpu_name = re.sub(r"\s+with .*", "", cpu.get("model name", "")).replace("(R)", "").replace("(TM)", "")
    max_khz = read(SYS / "devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
    cpu_bits = [f"{cpu.get('cpu cores', '?')} cores", f"{cpu.get('siblings', '?')} threads"]
    if max_khz.isdigit():
        cpu_bits.append(f"up to {int(max_khz) / 1e6:.1f} GHz")

    devs = pci_devices()
    laptop = chassis in ("Laptop", "Convertible")
    gpus, net = [], []
    for x in devs:
        c = x["class"]
        label = f"{short_vendor(x['vendor'])} {clean_device(x['name'], laptop)}".strip() if x["name"] else ""
        if not label:
            continue
        if c.startswith("0x03"):
            vram = read(x["path"] / "mem_info_vram_total")
            drv = os.path.basename(os.path.realpath(x["path"] / "driver")) if (x["path"] / "driver").exists() else ""
            kind = "dedicated" if drv.startswith("nvidia") or drv == "nouveau" else "integrated" \
                if any(g in x["name"] for g in ("Renoir", "Vega", "Radeon Graphics", "UHD", "Iris")) or vram and int(vram) < 2**30 else ""
            extra = [kind.capitalize()] if kind else []
            if vram.isdigit() and int(vram) >= 2**30:
                extra.append(gb(int(vram)) + " video memory")
            gpus.append([label, " · ".join(extra)])
        elif c.startswith("0x0280"):
            net.append(("Wi-Fi", label))
        elif c.startswith("0x0200"):
            net.append(("Ethernet", label))
    for d in sorted((SYS / "class/bluetooth").glob("hci*")):
        net.append(("Bluetooth", "Built in"))
        break

    disks = []
    for b in sorted((SYS / "block").glob("*")):
        n = b.name
        if n.startswith(("loop", "zram", "ram", "dm-", "sr")):
            continue
        size = int(read(b / "size", "0") or 0) * 512
        if size <= 0:
            continue
        model = read(b / "device/model") or read(b / "device/name")
        rota = read(b / "queue/rotational") == "1"
        kind = "NVMe SSD" if n.startswith("nvme") else ("Hard disk" if rota else "SSD")
        if read(b / "removable") == "1":
            kind = "Removable"
        disks.append([f"{gb(size)} {kind}", model])

    os_name = "Linux"
    for line in read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            os_name = line.split("=", 1)[1].strip('"')

    return {
        "vendor": vendor, "family": family, "product": product, "chassis": chassis,
        "bios": " · ".join(x for x in (read(dmi / "bios_version"), read(dmi / "bios_date")) if x),
        "board": read(dmi / "board_name"),
        "serial": serial_number(),
        "ram": ram_modules(),
        "cpu": cpu_name, "cpu_detail": ", ".join(cpu_bits),
        "gpus": gpus, "net": net, "disks": disks,
        "os": os_name, "kernel": os.uname().release,
    }


def cached_static():
    boot = read("/proc/sys/kernel/random/boot_id")
    try:
        c = json.loads(CACHE.read_text())
        if c.get("_boot") == boot:
            return c
    except (OSError, ValueError):
        pass
    s = static_info()
    s["_boot"] = boot
    if not s.get("serial"):        # hostnamed was slow or refused: ask again next time
        return s
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(s))
    except OSError:
        pass
    return s


# ---- live facts --------------------------------------------------------------------------
def memory():
    m = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        m[k] = int(v.split()[0]) * 1024 if v.split() else 0
    total, avail = m.get("MemTotal", 0), m.get("MemAvailable", 0)
    # installed RAM is a round number above what the kernel reports (it reserves some, and
    # the iGPU takes its share)
    installed = next((s for s in (4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128) if s * 2**30 >= total), 0)
    txt = f"{installed} GB" if installed else gb(total)
    used = total - avail
    swaps = []
    for line in read("/proc/swaps").splitlines()[1:]:
        f = line.split()
        if len(f) >= 3:
            kind = "zram" if "zram" in f[0] else ("file" if f[1] == "file" else "partition")
            swaps.append(f"{int(f[2]) * 1024 / 2**30:.1f} GB {kind}")
    return f"{txt} · {used / 2**30:.1f} GB in use", " + ".join(swaps)


def battery():
    for b in sorted((SYS / "class/power_supply").glob("*")):
        if read(b / "type") != "Battery" or read(b / "scope") == "Device":
            continue
        full = read(b / "energy_full") or read(b / "charge_full")
        design = read(b / "energy_full_design") or read(b / "charge_full_design")
        unit = "Wh" if read(b / "energy_full") else "Ah"
        rows = []
        cap, status = read(b / "capacity"), read(b / "status")
        if cap:
            rows.append(["Charge", f"{cap} %" + (f" · {status.lower()}" if status and status != "Unknown" else "")])
        if full.isdigit() and design.isdigit() and int(design):
            health = 100 * int(full) / int(design)
            rows.append(["Health", f"{health:.0f} % · {int(full) / 1e6:.1f} of {int(design) / 1e6:.1f} {unit}"])
        cyc = read(b / "cycle_count")
        if cyc.isdigit() and int(cyc) > 0:
            rows.append(["Charge cycles", cyc])
        model = " ".join(x for x in (read(b / "manufacturer"), read(b / "model_name"), read(b / "technology")) if x)
        if model:
            rows.append(["Cell", model])
        return rows
    return []


def displays():
    try:
        mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True,
                                         timeout=3).stdout or "[]")
    except Exception:
        return []
    rows = []
    for m in mons:
        name = "Built-in" if m.get("name", "").startswith(("eDP", "LVDS", "DSI")) else m.get("name", "Display")
        maker = " ".join(x for x in (m.get("make", ""), m.get("model", "")) if x and not x.startswith("0x"))
        val = f"{m['width']}×{m['height']} · {round(m['refreshRate'])} Hz"
        if m.get("scale", 1) != 1:
            val += f" · {m['scale']:g}× scale"
        if maker:
            val += f" · {maker}"
        rows.append([name, val])
    return rows


def uptime():
    s = int(float(read("/proc/uptime", "0").split()[0]))
    d, h, mi = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return " ".join(x for x in (f"{d} d" if d else "", f"{h} h" if h else "", f"{mi} min") if x)


def main():
    s = cached_static()
    mem, swap = memory()
    groups = [
        {"title": "Device", "rows": [r for r in [
            ["Model", f"{s['vendor']} {s['family']}".strip()],
            ["Machine type", s["product"]] if s["product"] else None,
            ["Serial number", s.get("serial", ""), "Click to copy", "copy"] if s.get("serial") else None,
            ["Form", s["chassis"]],
            ["Firmware (BIOS)", s["bios"]] if s["bios"] else None,
        ] if r]},
        {"title": "Performance", "rows": [r for r in [
            ["Processor", s["cpu"], s["cpu_detail"]],
            *[["Graphics", g[0], g[1]] for g in s["gpus"]],
            ["Memory", mem, s.get("ram", "")],
            ["Swap", swap] if swap else None,
        ] if r]},
        {"title": "Storage", "rows": [["Disk", d[0], d[1]] for d in s["disks"]]},
        {"title": "Displays", "rows": displays()},
        {"title": "Battery", "rows": battery()},
        {"title": "Connectivity", "rows": [list(n) for n in s["net"]]},
        {"title": "Software", "rows": [["System", s["os"]], ["Kernel", s["kernel"]], ["Up for", uptime()]]},
    ]
    print(json.dumps({"device": {"name": f"{s['vendor']} {s['family']}".strip(), "chassis": s["chassis"],
                                 "summary": " · ".join(x for x in (s["cpu"].replace("AMD ", "").replace("Intel ", ""),
                                                                    mem.split(" ·")[0]) if x)},
                      "groups": [g for g in groups if g["rows"]]}))


if __name__ == "__main__":
    main()
