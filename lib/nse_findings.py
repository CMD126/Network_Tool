"""Count structured Nmap vulns-library findings, never free-form prose."""

import sys
import xml.etree.ElementTree as ET


def count_findings(path):
    root = ET.parse(path).getroot()
    if root.tag != "nmaprun":
        raise ValueError("expected an nmaprun document")
    finished = root.find("runstats/finished")
    if finished is None or finished.get("exit") != "success":
        raise ValueError("Nmap did not finish successfully")
    # Each finding table is one report, even if it has multiple references
    # or repeats the state. Never interpret the human-readable output attr.
    return sum(
        1
        for script in root.iter("script")
        for table in script.iter("table")
        if any(
            elem.get("key") == "state"
            and (elem.text or "").strip().upper() in {"VULNERABLE", "LIKELY VULNERABLE"}
            for elem in table.findall("elem")
        )
    )


if __name__ == "__main__":
    try:
        print(count_findings(sys.argv[1]))
    except (OSError, ET.ParseError, ValueError, IndexError) as exc:
        print(f"nse_findings: {exc}", file=sys.stderr)
        sys.exit(1)
