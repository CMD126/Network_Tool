"""Offline regressions for structured NSE result counting."""

import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "nse_findings", Path(__file__).resolve().parents[1] / "lib/nse_findings.py"
)
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)


class FindingsTests(unittest.TestCase):
    def count(self, scripts, finished='<finished exit="success"/>'):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scan.xml"
            path.write_text(
                '<nmaprun><host><ports><port><script id="vuln-test" '
                'output="NOT VULNERABLE; see VULNERABLE documentation">'
                + scripts + '</script></port></ports></host><runstats>'
                + finished + '</runstats></nmaprun>'
            )
            return parser.count_findings(path)

    def test_negative_state_and_output_text_are_not_findings(self):
        self.assertEqual(self.count('<table><elem key="state">NOT VULNERABLE</elem></table>'), 0)

    def test_positive_state_is_one_finding(self):
        self.assertEqual(self.count('<table key="CVE-A"><elem key="state">VULNERABLE</elem></table>'), 1)

    def test_multiple_findings_nested_references_and_duplicate_state(self):
        tables = '<table><elem key="state">VULNERABLE</elem><elem key="state">VULNERABLE</elem><table key="refs"><elem>CVE-A</elem></table></table>'
        tables += '<table><elem key="state">LIKELY VULNERABLE</elem></table>'
        tables += '<table><elem key="state">NOT VULNERABLE</elem></table>'
        self.assertEqual(self.count(tables), 2)

    def test_unknown_or_text_only_is_not_counted(self):
        self.assertEqual(self.count('<table><elem key="state">UNKNOWN</elem></table>'), 0)

    def test_failed_run_is_not_a_clean_zero(self):
        with self.assertRaises(ValueError):
            self.count('', '<finished exit="error"/>')

    def test_missing_finished_is_not_a_clean_zero(self):
        with self.assertRaises(ValueError):
            self.count('', '')

    def test_malformed_xml_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scan.xml"
            path.write_text('<nmaprun><host>')
            with self.assertRaises(parser.ET.ParseError):
                parser.count_findings(path)


if __name__ == "__main__":
    unittest.main()
