"""Run the portable offline suite from any working directory."""
from pathlib import Path
import subprocess
import sys
import time
from lupa.lua53 import LuaRuntime

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime()
parse=lua.eval('function(s) local f,e=load(s);assert(f,e) end')
scripts=list((root/'scripts').rglob('*.lua'))
for p in scripts: parse(p.read_text(encoding='utf-8'))
print(f'PASS Lua 5.3 syntax: {len(scripts)} scripts',flush=True)
failures=[]
for test in sorted((root/'tests').glob('test_*.py')):
    start=time.monotonic()
    print(f'\n=== {test.name} ===',flush=True)
    result=subprocess.run([sys.executable,str(test)],cwd=root)
    if result.returncode: failures.append(test.name)
    print(f'{test.name}: exit {result.returncode}, {time.monotonic()-start:.2f}s',flush=True)
if failures: raise SystemExit('FAILED: '+', '.join(failures))
print('\nPASS all offline checks. Editor, mobile, asset delivery and real multiplayer require device validation.')
