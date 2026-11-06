"""Verify/restore the saved forest runtime into an explicitly selected editor project.

Dry run by default. Close the editor before --apply. This is a project-file migration,
not an official .mix importer. Published world identity and accounts are never copied.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def safe_path(root, relative):
    p = (root / relative).resolve()
    if p == root.resolve() or root.resolve() not in p.parents:
        raise ValueError(f'Unsafe package path: {relative}')
    return p

def verify(root=ROOT):
    m = json.loads((root/'manifest.json').read_text(encoding='utf-8'))
    for relative, expected in m['files'].items():
        p = safe_path(root, relative)
        if hashlib.sha256(p.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Checksum mismatch: {relative}')
    with zipfile.ZipFile(root/'scene/forest.scene.data') as z:
        if z.testzip(): raise ValueError('Corrupted scene ZIP')
        d = json.loads(z.read('SerializePcgData.json'))
        for resource in d['resourceRefs']:
            if resource['resourceType'] == 1 and resource['pathOrUrl'] not in z.namelist():
                raise ValueError(f'Missing scene resource: {resource["pathOrUrl"]}')
    assert len(m['scripts']) == len(d['runtimeScripts']), 'Script inventory mismatch'
    for entry in m['scripts']:
        assert safe_path(root,entry['path']).read_text(encoding='utf-8') == d['runtimeScripts'][entry['key']]['content'], entry['path']
    print(f'OK: {len(m["scripts"])} scripts match the saved scene; all package hashes valid')
    return m

def install(project, mode='full', apply=False, root=ROOT):
    manifest = verify(root)
    project = project.resolve()
    if project == root.resolve() or root.resolve() in project.parents:
        raise ValueError('Destination cannot be inside the repository')
    if not (project/'project.json').is_file() or not (project/'scene.data').is_file():
        raise ValueError('Choose an existing, saved editor project directory (project.json + scene.data)')
    files = {entry['path']:safe_path(root,entry['path']).read_bytes() for entry in manifest['scripts']}
    if mode == 'full':
        files['scene.data'] = (root/'scene/forest.scene.data').read_bytes()
        settings = root/'settings/env-param-overrides.json'
        if settings.exists(): files['settings/env-param-overrides.json'] = settings.read_bytes()
    else:
        # Require existing identical scene script bindings. Never inject these into a new map.
        with zipfile.ZipFile(project/'scene.data') as z:
            scene = json.loads(z.read('SerializePcgData.json'))
        for e in manifest['scripts']:
            old = scene['runtimeScripts'].get(e['key'])
            if not old or old['referencePath'] != e['referencePath']:
                raise ValueError('Scene binding mismatch; scripts mode requires the migrated forest base')
        # Source updates are picked up and embedded on the next editor save.
    for relative in files: safe_path(project, relative)
    print(f'{"APPLY" if apply else "DRY RUN"}: {mode}, {len(files)} files -> {project}')
    if not apply: return None
    backup = Path(tempfile.mkdtemp(prefix=project.name+'-before-gameplay-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-', dir=project.parent))
    touched = []
    try:
        for relative, content in files.items():
            target = safe_path(project,relative)
            saved = backup/relative
            if target.exists():
                saved.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(target,saved)
            target.parent.mkdir(parents=True,exist_ok=True)
            touched.append(relative)
            with tempfile.NamedTemporaryFile(dir=target.parent,delete=False) as f:
                f.write(content); temp = Path(f.name)
            temp.replace(target)
        (backup/'restore.json').write_text(json.dumps({'destination':str(project),'files':touched},indent=2),encoding='utf-8')
    except Exception:
        for relative in reversed(touched):
            saved = backup/relative; target = project/relative
            if saved.exists(): shutil.copy2(saved,target)
            elif target.exists(): target.unlink()
        raise
    for relative,content in files.items():
        assert (project/relative).read_bytes() == content, relative
    print(f'Installed and verified. Backup: {backup}')
    print('Open the destination project, save once, then run local preview. Asset downloads require the editor account.')
    return backup

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['verify','install'])
    p.add_argument('--project', type=Path)
    p.add_argument('--mode',choices=['full','scripts'],default='full')
    p.add_argument('--apply',action='store_true')
    p.add_argument('--editor-closed',action='store_true')
    a=p.parse_args()
    if a.command=='verify': verify();return
    if a.project is None: p.error('--project is required')
    if a.apply and not a.editor_closed: p.error('Close the editor first, then pass --editor-closed')
    install(a.project,a.mode,a.apply)

if __name__=='__main__': main()
