"""Export only the saved, bound runtime; never export editor sessions or credentials."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def script_path(reference):
    p = PurePosixPath(reference)
    if p.is_absolute() or '..' in p.parts or '\\' in reference:
        raise ValueError(f'Unsafe reference: {reference}')
    return ('scripts/' if reference.startswith(('modules/', 'runtime-builtin/'))
            else 'scripts/client/') + reference

def export(project, output=ROOT):
    scene = project / 'scene.data'
    with zipfile.ZipFile(scene) as z:
        data = json.loads(z.read('SerializePcgData.json'))
    entries = []
    # Validate before making any output. Unsaved edits must not silently be discarded.
    for key, value in data['runtimeScripts'].items():
        relative = script_path(value['referencePath'])
        source = project / relative
        content = value['content']
        if source.exists() and source.read_text(encoding='utf-8') != content:
            raise ValueError(f'Unsaved script: {relative}; save the editor scene first')
        entries.append(dict(key=key, path=relative, referencePath=value['referencePath'],
                            referenceName=value.get('referenceName'), content=content))
    for entry in entries:
        target = output / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(entry.pop('content'), encoding='utf-8')
    (output / 'scene').mkdir(parents=True, exist_ok=True)
    shutil.copy2(scene, output / 'scene/forest.scene.data')
    settings = project / 'settings/env-param-overrides.json'
    if settings.exists():
        (output / 'settings').mkdir(exist_ok=True)
        shutil.copy2(settings, output / 'settings/env-param-overrides.json')
    roots = [dict(name=n['nodeName'], id=n['id'], position=n['pos'],
                  asset=n.get('assetData')) for n in data['nodeTransformDatas'] if n['parentId'] == 0]
    (output / 'bindings').mkdir(exist_ok=True)
    (output / 'bindings/scene-roots.json').write_text(json.dumps(roots, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    assets = []
    for n in data['nodeTransformDatas']:
        if n.get('assetData'):
            assets.append(dict(node=n['nodeName'], id=n['id'], asset=n['assetData']))
    (output / 'bindings/assets.json').write_text(json.dumps(assets, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    paths = [e['path'] for e in entries] + ['scene/forest.scene.data', 'bindings/scene-roots.json', 'bindings/assets.json']
    if settings.exists(): paths.append('settings/env-param-overrides.json')
    manifest = dict(format=1, title='仔仔塔防—森林篇', editorVersion='1.0.0',
                    snapshotDate='2026-11-06', scripts=entries,
                    files={p:digest(output/p) for p in sorted(paths)})
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Exported {len(entries)} saved scripts, {len(roots)} roots, {len(assets)} asset bindings')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True)
    args = parser.parse_args()
    export(args.project.resolve())
