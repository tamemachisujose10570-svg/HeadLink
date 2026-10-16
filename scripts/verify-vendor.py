#!/usr/bin/env python3
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads((root/'Vendor/manifest.json').read_text())
assert manifest['OpenCine']['commit']=='acc38b57d43d4308c79ad5ce951bcb6f44d14d68'
expected=manifest['sha256']
actual={str(p.relative_to(root/'Vendor/OpenCine')):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in (root/'Vendor/OpenCine').rglob('*') if p.is_file()}
assert actual==expected, 'Vendored dependency changed. Review the diff and update manifest explicitly.'
print(f'Vendor verified: {len(actual)} files, fixed OpenCine revision and documented local patches')
