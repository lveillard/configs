"""Reject real infrastructure identifiers in files tracked for publication.

This complements a secret scanner. Keep real settings in ignored local files.
Diagnostics name the location and category, never the matched value.
"""
import ipaddress
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    'cloud identifier': re.compile(r'\b[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\b'),
    'private Tailscale domain': re.compile(r'\b(?:[\w-]+\.)+ts\.net\b'),
    'personal user path': re.compile(r'(?:/home/|[A-Za-z]:[/\\]Users[/\\])([\w.-]+)'),
    'private key': re.compile(r'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----'),
}
LOCAL_FILES = {'boxes.json', 'server.json', 'auth.json', 'secrets.json', 'credentials.json'}
EXAMPLE_NETWORKS = [ipaddress.ip_network(n) for n in ('192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24')]


def issues(path, text):
    if path.name in LOCAL_FILES or path.name.endswith(('.tfstate', '.tfvars', '.local.json')):
        yield 1, 'local-only file'
    for line_number, line in enumerate(text.splitlines(), 1):
        for category, pattern in PATTERNS.items():
            for match in pattern.finditer(line):
                value = match.group()
                if category == 'cloud identifier' and value == '00000000-0000-0000-0000-000000000000':
                    continue
                if category == 'private Tailscale domain' and value == 'your-tailnet.ts.net':
                    continue
                if category == 'personal user path' and match[1] == 'devuser':
                    continue
                yield line_number, category
        for match in re.finditer(r'\b(?:\d{1,3}\.){3}\d{1,3}\b', line):
            try:
                address = ipaddress.ip_address(match.group())
            except ValueError:
                continue
            if address.is_global and not any(address in network for network in EXAMPLE_NETWORKS):
                yield line_number, 'public IP address'


def main():
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    findings = []
    for name in filter(None, names):
        path = ROOT / name
        for line, category in issues(Path(name), path.read_text(encoding='utf-8')):
            findings.append(f'{name}:{line}: {category}')
    if findings:
        print('\n'.join(findings))
        return 1
    print('Public-data check passed: no real IPs, cloud IDs, tailnets or personal user paths detected.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
