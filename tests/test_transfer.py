from pathlib import Path
import importlib.util
import json
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location('transfer', 'tools/transfer.py')
t = importlib.util.module_from_spec(spec); spec.loader.exec_module(t)
m=t.verify()
with tempfile.TemporaryDirectory() as tmp:
    project=Path(tmp)/'empty-editor-project';project.mkdir()
    (project/'project.json').write_text('{"name":"New World"}')
    (project/'world-config.json').write_text('{"worldId":"new-world-not-forest"}')
    with zipfile.ZipFile(project/'scene.data','w') as z:
        z.writestr('SerializePcgData.json',json.dumps({'runtimeScripts':{}}))
    old=(project/'scene.data').read_bytes()
    assert t.install(project) is None
    assert (project/'scene.data').read_bytes()==old and not (project/'scripts').exists()
    backup=t.install(project,apply=True)
    assert (backup/'scene.data').read_bytes()==old
    assert json.loads((project/'world-config.json').read_text())['worldId']=='new-world-not-forest'
    assert json.loads((project/'project.json').read_text())['name']=='New World'
    assert (project/'scene.data').read_bytes()==(t.ROOT/'scene/forest.scene.data').read_bytes()
    for entry in m['scripts']:
        assert (project/entry['path']).read_bytes()==(t.ROOT/entry['path']).read_bytes()
    t.install(project,mode='scripts')
    try: t.safe_path(project,'../outside')
    except ValueError: pass
    else: raise AssertionError('path escape accepted')
    print('PASS dry run, backup, full restore, exact scripts, preserved world identity, scripts mode, path safety')
