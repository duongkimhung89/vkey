#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p reports
python3 - <<'PY'
from pathlib import Path
import re
pattern=r'URLSession|NSURLSession|NWConnection|WebSocket|Sparkle|NSPasteboard|FileHandle|CGEvent|AXIsProcessTrusted|NSLog|os_log|\bprint\s*\(|\bProcess\s*\(|\bNSTask\b|import Network|\bsocket\s*\(|\bconnect\s*\('
hits=[]
for p in Path('Sources').rglob('*.swift'):
 for n,line in enumerate(p.read_text().splitlines(),1):
  if re.search(pattern,line): hits.append(f'{p}:{n}: {line}')
Path('reports/source-audit.txt').write_text('\n'.join(hits) if hits else 'PASS: no disallowed API pattern in production source. This scan supplements manual review; it is not a formal proof.\n')
if hits: raise SystemExit('\n'.join(hits))
PY
otool -L dist/VKey.app/Contents/MacOS/VKey > reports/linked-libraries.txt
nm -u dist/VKey.app/Contents/MacOS/VKey > reports/undefined-symbols.txt
codesign -dvvv --entitlements - dist/VKey.app > reports/signing.txt 2>&1
codesign --verify --strict dist/VKey.app
