from pathlib import Path
import hashlib
import json
import sys

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf8'))
errors = []
for item in manifest['files']:
    file = root / item['path']
    if not file.is_file() or file.stat().st_size != item['bytes']:
        errors.append(item['path'])
    elif hashlib.sha256(file.read_bytes()).hexdigest() != item['sha256']:
        errors.append(item['path'])
print(json.dumps({'files': len(manifest['files']), 'passed': not errors, 'failures': errors}))
sys.exit(bool(errors))
