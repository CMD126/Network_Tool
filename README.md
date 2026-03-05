# Network Tool Pro

A powerful bash-based network diagnostic suite for daily use, with an interactive menu covering interface analysis, DNS, scanning, web/TLS inspection, and live monitoring.

## Features

| Category | Capabilities |
|----------|-------------|
| **Quick** | Dashboard — public IP, interface, gateway, DNS, connectivity and open ports at a glance |
| **Network** | Interface info, routing table, ARP, local host discovery |
| **Connectivity** | Ping, traceroute, MTU discovery |
| **DNS** | Full record lookup (A/AAAA/MX/NS/TXT), reverse DNS, whois |
| **Scanning** | Port scan, service/OS version scan, vulnerability check (NSE) |
| **Web & TLS** | HTTP headers/stats, SSL certificate expiry + SANs, IP geolocation |
| **Monitoring** | Active connections, listening ports, speed test, live bandwidth (real-time) |

## Requirements

### Essential

- `ip` (iproute2)
- `ping`
- `curl`
- `ss`
- `openssl`

### Optional (for full functionality)

- `nmap` — port scan, service scan, vuln check
- `traceroute` or `tracepath` — hop-by-hop path
- `dig` / `nslookup` / `host` — DNS lookups
- `whois` — domain/IP registration info
- `python3` — geolocation JSON parsing

## Installation

```bash
# Clone
git clone https://github.com/lexlucas/Network_Tool.git
cd Network_Tool

# Make executable
chmod +x networktool.sh

# Install dependencies (Debian/Ubuntu)
sudo apt install nmap traceroute dnsutils iproute2 curl whois openssl

# Install dependencies (RHEL/CentOS)
sudo yum install nmap traceroute bind-utils iproute curl whois openssl
```

## Usage

```bash
# Normal user
./networktool.sh

# Root (enables SYN scans + OS detection)
sudo ./networktool.sh
```

## Menu Reference

| # | Function | Description |
|---|----------|-------------|
| **1** | Dashboard | Public IP, primary interface, gateway, DNS servers, connectivity to 8.8.8.8/1.1.1.1/google.com, top open ports |
| **2** | Interface Info | All interfaces — IP, MAC, state (UP/DOWN), RX/TX byte stats |
| **3** | Routing Table | Default gateway, full route table, ARP/neighbour cache |
| **4** | Local Discovery | nmap ping sweep of a subnet to find live hosts and MACs |
| **5** | Ping | ICMP test with configurable packet count |
| **6** | Traceroute | Hop-by-hop path (falls back to `tracepath`) |
| **7** | MTU Discovery | Probes common MTU sizes (1500 → 576) with DF-bit ping |
| **8** | DNS Lookup | A, AAAA, MX, NS, TXT records + configured DNS servers |
| **9** | Reverse DNS | PTR lookup for any IP |
| **10** | Whois | Domain/IP registration (falls back to RDAP if whois not installed) |
| **11** | Port Scan | Open ports via nmap (SYN as root, TCP connect as user) |
| **12** | Service Scan | Service versions + OS detection |
| **13** | Vuln Check | nmap NSE `vuln,auth,default` scripts with authorization prompt |
| **14** | HTTP Check | Status code, response headers, redirect chain, timing, speed |
| **15** | SSL Certificate | Expiry countdown, issuer, Subject Alternative Names, cipher suite |
| **16** | IP Geolocation | Country, city, ASN, org, timezone via ipinfo.io |
| **17** | Active Connections | All established TCP/UDP sessions with process names |
| **18** | Listening Ports | Services bound and waiting, TCP + UDP |
| **19** | Speed Test | Download bandwidth in Mbps (Hetzner test endpoints) |
| **20** | Live Bandwidth | Real-time RX/TX bytes/s and Kbps per interface |
| **21** | View Log | Last 30 entries from `networktool.log` |
| **22** | Export Result | Save last command output to `last_result.txt` |
| **0** | Exit | |

## Configuration

Edit these variables at the top of `networktool.sh`:

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `<script_dir>/networktool.log` | Log file path |
| `RESULTS_FILE` | `<script_dir>/last_result.txt` | Export file path |
| `DEFAULT_PING_COUNT` | `4` | Ping packet count |
| `DEFAULT_PORTS` | `1-1000` | nmap port range |
| `DEFAULT_TIMEOUT` | `10` | Seconds before timeout |

## Common Workflows

### Quick network health check
```
1 → Dashboard
```

### Troubleshoot connectivity
```
5 → Ping gateway
6 → Traceroute to failing host
8 → Verify DNS resolves correctly
```

### Inspect a server
```
11 → Port scan
12 → Service/OS fingerprint
15 → Check SSL cert expiry
14 → Inspect HTTP headers
```

### Monitor live traffic
```
20 → Live bandwidth on primary interface
17 → Active connections
18 → Listening ports
```

## Notes

- **Legal**: Only scan hosts and networks you own or have explicit written permission to test.
- **Root**: Required for SYN scans (`-sS`) and OS detection. Non-root falls back to TCP connect scans.
- **Logs**: `networktool.log` records all actions with timestamps. May contain sensitive info — handle accordingly.
- **Temp files**: Created under `/tmp/nettool_<pid>` and cleaned up automatically on exit.

## Version History

| Version | Changes |
|---------|---------|
| 3.0 | Full rewrite — 22-function daily-use suite with TLS, geolocation, live bandwidth, MTU, vuln check |
| 2.1 | Bug fixes — dig syntax, speed test endpoints, ip -color, log path, MTU, scan quoting |
| 2.0 | Enhanced features, improved logging, better error handling |
| 1.0 | Initial release |

## Author

Created by [@lexlucas](https://github.com/lexlucas)

## License

For educational and legitimate diagnostic purposes only. Users are responsible for complying with all applicable laws and regulations.

> **Disclaimer**: Use this tool responsibly and only on networks you own or have explicit permission to test. Unauthorized scanning may be illegal in your jurisdiction.
