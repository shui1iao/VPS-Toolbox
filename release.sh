#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'HELP'
Usage: ./release.sh <version> "release notes"

Example:
  ./release.sh 0.1.5 "修复脚本输入校验并更新文档。"
HELP
}

version="${1:-}"
notes="${2:-}"
if [[ -z "$version" || -z "$notes" || "$version" == "-h" || "$version" == "--help" ]]; then
	usage
	exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "version must be semantic version like 0.1.2" >&2
	exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
	echo "working tree is not clean" >&2
	git status --short
	exit 1
fi

python3 - "$version" "$notes" <<'PYHELP'
import datetime, json, re, sys
from pathlib import Path

version, notes = sys.argv[1], sys.argv[2]
root = Path('.')

if (root / 'version.txt').exists():
    (root / 'version.txt').write_text(version + '\n', encoding='utf-8')

for path in root.glob('*.sh'):
    if path.name == 'release.sh':
        continue
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'^(VERSION=")([0-9]+\.[0-9]+\.[0-9]+)(".*)$', rf'\g<1>{version}\g<3>', text, flags=re.M)
    text = re.sub(r'^(SCRIPT_VERSION=")([0-9]+\.[0-9]+\.[0-9]+)(".*)$', rf'\g<1>{version}\g<3>', text, flags=re.M)
    path.write_text(text, encoding='utf-8')

for name in ['package.json', 'package-lock.json']:
    p = root / name
    if p.exists():
        data = json.loads(p.read_text(encoding='utf-8'))
        data['version'] = version
        if name == 'package-lock.json' and 'packages' in data and '' in data['packages']:
            data['packages']['']['version'] = version
        p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

changelog = root / 'CHANGELOG.md'
entry = f"## [{version}] - {datetime.date.today().isoformat()}\n\n- {notes}\n\n"
if changelog.exists():
    text = changelog.read_text(encoding='utf-8')
    if f'## [{version}]' not in text:
        if text.startswith('# Changelog\n\n'):
            text = '# Changelog\n\n' + entry + text[len('# Changelog\n\n'):]
        else:
            text = '# Changelog\n\n' + entry + text
    changelog.write_text(text, encoding='utf-8')
else:
    changelog.write_text('# Changelog\n\n' + entry, encoding='utf-8')
PYHELP

git add -A
git commit -m "Release v$version"
git tag -a "v$version" -m "v$version"
git push
git push origin "v$version"
