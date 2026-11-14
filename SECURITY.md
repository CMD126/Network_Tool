# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 4.x (`main`) | Yes |
| < 4.0 | No |

## Reporting a vulnerability

Please do not open a public issue with exploit details.

- Preferred: use **Report a vulnerability** on this repository's
  [Security tab](https://github.com/CMD126/Network_Tool/security) (GitHub
  private vulnerability reporting), if it is available.
- Otherwise: open an issue titled "Security contact request" with no
  technical details, and a private channel will be arranged.

Include the affected version or commit, the exact command line or config
value, what happened and what you expected. Fixes land on `main` together
with a regression test.

## Threat model

Network Tool Pro is a local, single-user CLI. It runs with the privileges of
whoever starts it (sometimes root, for SYN scans and OS detection), so any
way to turn *data* into *code* matters. Untrusted input reaches it through:

1. **Targets and options**: CLI arguments and interactive prompts (hosts,
   IPs, CIDRs, URLs, port lists, interface names, counts).
2. **The config file** (`~/.config/networktool/config.ini`).
3. **Output of external tools and remote services** (`dig`, `nmap`,
   `whois`, `openssl`, HTTP responses, ipinfo.io / RDAP JSON), which is
   printed to the terminal and embedded in JSON.

## How input is handled

- **Validate, then quote.** Every target goes through a `validate_*`
  function in [lib/utils.sh](lib/utils.sh) (IPv4/IPv6, domain, CIDR,
  http(s) URL, port/port list in 1-65535, interface name) before any command
  runs, and is always passed as a single quoted argument. There is no
  `eval` and no command built as a string. Interactive input is additionally
  stripped of shell metacharacters by `sanitize_input()` as defence in depth.
- **No option injection.** Validated hosts, URLs and interface names cannot
  start with `-`, so they cannot be read as options by `nmap`, `curl`,
  `ping` or `openssl`.
- **Arithmetic is fed only plain integers.** Bash evaluates the operands of
  `(( ))`, `$(( ))` and `[[ -gt ]]` as expressions, so a value like
  `x[$(cmd)]` would run `cmd`. Numeric CLI options and config values are
  checked against `^[0-9]+$` and normalised to base 10 before any
  arithmetic; invalid config values are ignored with a warning.
- **Safe output.** Rejected input is echoed through `printable()` (control
  characters replaced, backslashes neutralised) so it cannot inject terminal
  escape sequences. `json_escape()` escapes quotes, backslashes, newlines
  and tabs and drops other control characters, so `--json` output stays
  valid JSON whatever a remote service returns.
- **Consent before scanning.** Port and service scans of a non-private
  address print a warning and are refused without interactive confirmation
  or `--yes`; the vulnerability check always requires explicit consent.
- **Temporary files** live in a private `mktemp -d` directory that is
  removed on exit; the tool stops rather than fall back to a predictable
  path in `/tmp`.

Regression tests for these rules are in
[tests/test_security.bats](tests/test_security.bats) and
[tests/test_cli.bats](tests/test_cli.bats), and run in CI on every push.

## Out of scope

- Anything that already requires write access to your account (for example
  editing your shell profile, or `log_file` in your own config pointing at a
  file you can already write).
- Findings in third-party tools the script calls (`nmap`, `curl`, `dig`,
  `openssl`, ...); please report those upstream.
- Results of scanning systems you are not authorised to test. Only scan
  hosts and networks you own or have written permission to test.
