# Live USB Bench & Diagnostics

This folder contains small, single-purpose bash scripts used to quickly validate a new/returned unit (ports, thermals, RAM stability, memory bandwidth, and drive health). Formalized to quickly diagnose the viability of a mini PC's hardware.

**Intended environment:** **Ubuntu 25.10 Live USB** (booted from Ventoy).  
These scripts assume you have **internet access** in the live session (for `apt` and, for STREAM, `wget`).

---

## Quick Start (Ubuntu Live)

1) Boot into **Ubuntu 25.10 Live** (Try Ubuntu).  
2) Connect to the internet (Ethernet preferred).
3) Open a terminal, `cd` into this folder, and make scripts executable:

```bash
chmod +x *.sh
````

4. Run the tests you want (examples below). Most scripts require `sudo`.

---

## Recommended Acceptance Flow (High Signal, Low Time)

### 0) Manual checks (fast)

Do these first so you don’t waste time on a unit you’ll RMA:

* Test **all USB ports** with a USB stick (read/write) + mouse/keyboard
* Test **DisplayPort(s)** with a known-good cable + monitor
* Confirm **Ethernet** link + stable connectivity:

```bash
ping -c 60 1.1.1.1
```

### 1) RAM (separate step: Memtest86+)

From Ventoy, boot **Memtest86+** and run overnight (12–24h).

**PASS:** 0 errors
**FAIL:** any error → likely RAM stick, IMC, or board issue (RMA or swap RAM)

### 2) Live thermals (watch-only)

In one terminal, run:

```bash
sudo ./sensors.sh
```

This displays real-time temps/fans. Use it while CPU tests run in another terminal.

### 3) CPU sustained stability

In another terminal:

```bash
sudo ./test-cpu.sh
```

Output file: `test-cpu-<epoch>.txt`
Optional file: `turbostat-<epoch>.txt` (if available)

### 4) Memory bandwidth baseline (STREAM)

```bash
sudo ./test-stream.sh
```

Output file: `test-stream-<epoch>.txt`

### 5) NVMe or SATA health (SMART)

List disks first:

```bash
lsblk -o NAME,SIZE,MODEL,TYPE
```

Run drive health checks by specifying the device:

**NVMe:**

```bash
sudo ./test-nvme.sh /dev/nvme0
# or
sudo ./test-nvme.sh /dev/nvme0n1
```

**SATA (2.5" drive):**

```bash
sudo ./test-sata.sh /dev/sda
```

Outputs:

* `test-nvme-<epoch>.txt`
* `test-sata-<epoch>.txt`

---

## Files Produced

Each test (except `sensors.sh`) writes a timestamped log in the current directory:

* `test-cpu-<timestamp>.txt`
* `turbostat-<timestamp>.txt` (optional)
* `test-stream-<timestamp>.txt`
* `test-nvme-<timestamp>.txt`
* `test-sata-<timestamp>.txt`

---

## How to Interpret Results

### RAM (Memtest86+)

* **PASS:** 0 errors after many passes (overnight)
* **FAIL:** any error at all

### CPU (`test-cpu.sh`)

This runs `stress-ng` for 15 minutes. Use `sensors.sh` in another terminal to watch temps.

* **PASS:** No crash/hang/reboot; temps stabilize.
* **Watch-outs:**

  * If temps slam into high 90s°C constantly, consider BIOS thermal profile changes and/or repaste.
  * If the system reboots or locks, treat as potential hardware instability (or power/thermal issue).

### Memory bandwidth (`test-stream.sh`)

STREAM outputs four numbers: **Copy / Scale / Add / Triad** in MB/s.

* **Healthy for DDR4-3200 dual-channel in a micro:** typically

  * **Copy:** ~35,000–40,000 MB/s
  * **Triad/Add/Scale:** often ~25,000–30,000 MB/s (varies with compiler/store behavior)
* **Red flags:**

  * Much lower results (e.g., Triad ~15,000–20,000 MB/s) can suggest single-channel, power limits, or throttling.
  * If results drop sharply on repeated runs, you may be thermally/power throttling.

*Note:* Copy often appears higher than Triad/Add because of how stores and cache write-allocate behave; this is normal.

### NVMe (`test-nvme.sh`)

Key fields to scan (in `nvme smart-log` / `smartctl` output):

* `critical_warning` should be **0**
* `media_errors` should be **0**
* `percentage_used` should be low (near **0** for new drives)
* `data_units_written` gives a rough “TB written” estimate

**PASS:** warnings/errors are 0 and wear is low
**FAIL:** non-zero critical warnings, rising media errors, lots of error log entries, or very high `percentage_used`

### SATA (`test-sata.sh`)

Key SMART attributes to scan:

* `Reallocated_Sector_Ct` = 0
* `Current_Pending_Sector` = 0
* `Offline_Uncorrectable` = 0

**PASS:** all the above are 0
**FAIL:** any non-zero values here are a bad sign for long-term reliability

---

## Notes / Assumptions

* These scripts are designed for **Ubuntu 25.10 Live USB** diagnostics.
* They install packages (`apt`) into the live environment (temporary).
* `test-nvme.sh` and `test-sata.sh` **require** a `/dev/...` argument and will exit with usage instructions if missing.
* STREAM downloads source code from UVA; requires internet.
* For long, deep RAM validation, rely on **Memtest86+** (outside the OS).

---

## Typical Run Examples

```bash
# Terminal 1 (live thermals)
sudo ./sensors.sh

# Terminal 2 (CPU)
sudo ./test-cpu.sh

# Memory bandwidth
sudo ./test-stream.sh

# Drive health
lsblk -o NAME,SIZE,MODEL,TYPE
sudo ./test-nvme.sh /dev/nvme0
sudo ./test-sata.sh /dev/sda
```

---

## Troubleshooting

* **No internet in Live session:** `apt` installs and STREAM download will fail.
* **Wrong disk path:** use `lsblk` to find the correct `/dev/...` device.
* **Permission issues:** run with `sudo`.

