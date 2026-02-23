🌍 English | 🇮🇷 [نسخه فارسی](README_FA.md)

# 🚀 emad

A lightweight, high-performance **reverse TCP tunnel manager** for connecting an **IRAN server** to a **foreign server** with stable long-running links, slot-based profiles, and simple operations.

---

## Table of Contents

1. [What is emad?](#what-is-emad)
2. [How it Works](#how-it-works)
3. [Core Features](#core-features)
4. [Architecture & Data Flow](#architecture--data-flow)
5. [Project Structure](#project-structure)
6. [Installation](#installation)
7. [Quick Start (Step-by-Step)](#quick-start-step-by-step)
8. [Manager Menu Guide](#manager-menu-guide)
9. [Configuration Profiles](#configuration-profiles)
10. [Performance & Optimization](#performance--optimization)
11. [Health Check & Auto Restart](#health-check--auto-restart)
12. [Port Forwarding Methods](#port-forwarding-methods)
13. [Security Recommendations](#security-recommendations)
14. [Troubleshooting](#troubleshooting)
15. [What Changed Recently](#what-changed-recently)
16. [FAQ](#faq)

---

## What is emad?

**emad** is a reverse TCP tunneling system designed to connect:

- 🇮🇷 **IRAN Server** (inside/entry side)
- 🌍 **EU/Foreign Server** (outside/service side)

It keeps persistent reverse links between servers, supports automatic port sync, and provides a simple shell manager for creating/running tunnel profiles.

---

## How it Works

The system uses two TCP channels:

| Channel | Purpose | Default |
|---|---|---|
| Bridge Port | Main reverse tunnel traffic | `7000` |
| Sync Port | AutoSync metadata (port announcements) | `7001` |

At runtime:

1. The foreign server opens reverse bridge connections to IRAN.
2. IRAN keeps those sockets in a pool.
3. When a client hits an open IRAN port, IRAN assigns one bridge socket and signals target port.
4. Foreign side connects locally to the target service and forwards traffic both ways.

---

## Core Features

| Feature | Description |
|---|---|
| Reverse TCP Tunnel | Persistent IRAN ⇄ Foreign connectivity |
| Multi-Slot Profiles | Up to 10 saved slots per role |
| AutoSync | Automatically syncs listening service ports |
| Manual Port Mode | Fixed CSV ports when AutoSync is disabled |
| Health Check (Cron) | Periodic monitor + auto restart |
| systemd-friendly workflow | Works well with server boot/start flows |
| Network optimization helpers | BBR/sysctl tuning menu option |
| Improved runtime logging | Better operational visibility |

---

## Architecture & Data Flow

```text
Client -> IRAN Server <==== Reverse Bridge TCP ====>> Foreign Server
               |                                          |
               +-- open IRAN listener ports               +-- local services (127.0.0.1:PORT)

AutoSync:
Foreign Server --(Sync TCP frames)--> IRAN Server
```

### Role Summary

| Role | Main Responsibility |
|---|---|
| IRAN | Accept bridge sockets, expose public listening ports, map traffic |
| Foreign | Keep reverse workers alive, connect local services, send AutoSync updates |

---

## Project Structure

| File | Purpose |
|---|---|
| `Pahlavi.py` | Core tunnel engine (IR/EU runtime, bridge, sync, pool) |
| `Pahlavi-Tunnel.sh` | Interactive manager (profiles, start/stop, health-check, optimize) |
| `install.sh` | Remote bootstrap installer |
| `README.md` | English documentation |
| `README_FA.md` | Persian documentation |

---

## Installation

Install on **both servers**:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/emad1381/Pahlavi-tunnel/main/install.sh)
```

Then open manager:

```bash
sudo emad
```

---

## Quick Start (Step-by-Step)

## 1) Prepare IRAN server

1. Run `sudo emad`
2. Choose `1) Create or update profile`
3. Select role `IRAN`
4. Select slot (e.g. `iran1`)
5. Set bridge/sync ports (defaults: `7000`/`7001`)
6. Choose AutoSync:
   - `y` for automatic service discovery from foreign server
   - `n` for manual CSV ports (example: `80,443,8443`)

## 2) Prepare Foreign server

1. Run `sudo emad`
2. Choose `1) Create or update profile`
3. Select role `EU`
4. Select matching slot number (e.g. `eu1`)
5. Enter IRAN public IP
6. Enter the **same** bridge and sync ports

## 3) Start tunnel

On each side:

1. `2) Manage tunnel and slots`
2. Pick role/slot
3. Select `2) Start`
4. Check `5) Status`

---

## Manager Menu Guide

### Main Menu

| Option | Action |
|---|---|
| 1 | Create or update profile |
| 2 | Manage tunnel and slots |
| 3 | Enable auto health-check (cron) |
| 4 | Disable auto health-check (cron) |
| 5 | Install script system-wide |
| 6 | Self-update manager script |
| 7 | Uninstall manager script |
| 8 | Optimize server (BBR + sysctl) |
| 9 | Test Tunnel (smart pre-check) |
| 0 | Exit |

### Slot Management Menu

| Option | Action |
|---|---|
| 1 | Show profile |
| 2 | Start |
| 3 | Stop |
| 4 | Restart |
| 5 | Status |
| 6 | Logs (attach to screen session) |
| 7 | Delete slot |
| 0 | Back |

---

## Configuration Profiles

Profiles are stored under:

```bash
/etc/emad_manager/profiles/
```

Example files:

- `eu1.env`
- `iran1.env`

### Profile Fields

| Field | Used By | Meaning |
|---|---|---|
| `ROLE` | all | `eu` or `iran` |
| `IRAN_IP` | EU | Public IP of IRAN server |
| `BRIDGE` | all | Main tunnel port |
| `SYNC` | all | AutoSync channel port |
| `AUTO_SYNC` | IRAN | `true`/`false` |
| `PORTS` | IRAN manual mode | CSV list of ports |

---

## Performance & Optimization

Pahlavi includes practical performance helpers:

| Area | Behavior |
|---|---|
| TCP tuning | Keepalive + socket buffer tuning in runtime |
| Pool sizing | Automatic pool sizing from system limits |
| Retry behavior | Reconnect loops with bounded backoff |
| System tuning | Optional BBR + sysctl optimization from manager |

Run optimization from menu:

```text
8) Optimize server (BBR + sysctl)
```

---

## Health Check & Auto Restart

Enable periodic health checks:

```text
3) Enable auto health-check (cron)
```

- You choose interval in minutes.
- If a slot process is missing, script restarts it automatically.
- Disable anytime with menu option `4`.

---

---

## Tunnel Pre-check (Option 9)

Use menu option `9) Test Tunnel (smart pre-check)` before creating/starting tunnels.

What it checks:

- DNS resolution for target IRAN endpoint
- TCP reachability for Bridge (and Sync when AutoSync is enabled)
- Multi-attempt probe with average RTT
- Readiness score and actionable final verdict

If you run it on an IRAN profile, the tool tries to find paired `euN` profile automatically for end-to-end checks.

When `AUTO_SYNC=false`, Sync-port probing is skipped by design, because IRAN does not need Sync listener in manual-port mode.

## Port Forwarding Methods

The project can be used alongside these forwarding methods:

| Method | Use Case |
|---|---|
| `iptables` (DNAT) | Simple kernel NAT forwarding |
| `nftables` | Modern packet filtering/forwarding |
| `HAProxy` (L4) | Managed TCP balancing/routing |
| `socat` | Quick relay and debugging |

---

## Security Recommendations

| Recommendation | Why |
|---|---|
| Open only required ports | Reduce attack surface |
| Protect bridge/sync ports with firewall | Avoid unauthorized access |
| Use strong SSH/admin hygiene | Protect hosts and configs |
| Monitor logs regularly | Detect drops/restarts early |
| Keep OS packages updated | Patch known vulnerabilities |

---

## Troubleshooting

### Service/Process Checks

```bash
systemctl status pahlavi
screen -ls
```

### Port and Socket Checks

```bash
ss -lntp
nc -zv IRAN_IP 7000
nc -zv IRAN_IP 7001
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| Tunnel not connecting | Bridge port blocked | Open firewall/security group on IRAN |
| AutoSync not working | Sync port mismatch/blocked | Ensure same `SYNC` on both sides |
| Intermittent drops | Network/provider instability | Enable health-check + tune kernel settings |
| No traffic to service | Service not listening on foreign server | Verify local service on `127.0.0.1:PORT` |

---

## What Changed Recently

### Runtime Engine (`Pahlavi.py`)

| Change | Benefit |
|---|---|
| Improved bridge forwarding path | Better performance under concurrency |
| Enhanced TCP behavior and retry handling | More resilient tunnel workers |
| Better operational logs | Easier debugging and monitoring |

### Manager UI (`Pahlavi-Tunnel.sh`)

| Change | Benefit |
|---|---|
| Better menu wording | Easier navigation |
| Input validation for ports/yes-no | Fewer configuration mistakes |
| Cleaner sectioned prompts | Improved UX for setup/edit flow |

---

## FAQ

### Do bridge/sync ports have to be identical on both servers?
Yes. Bridge and sync values must match for each slot pair.

### Can I run multiple independent tunnels?
Yes. Use different slot numbers (`1..10`).

### Will it survive reboots?
Yes, with proper manager setup and optional cron health-check.

### Can I use manual ports instead of AutoSync?
Yes. Disable AutoSync and provide CSV ports on IRAN profile.

---

## Final Notes

- Keep both sides synchronized when changing profile values.
- Start and verify both paired slots (`euN` + `iranN`).
- Use health-check and optimization options for production stability.

---

❤️ Maintained by emad
