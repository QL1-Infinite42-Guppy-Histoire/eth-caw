from pathlib import Path
import subprocess,tempfile,json,os
P=Path(__file__).resolve().parent
script=P/'install-node.sh'
text=script.read_text();start=text.index('# BEGIN reviewed-source');end=text.index('# END reviewed-source')
functions=text[start:end]
results=[]
def run(args,cwd=None):return subprocess.check_output(args,cwd=cwd,stderr=subprocess.STDOUT,text=True).strip()
with tempfile.TemporaryDirectory(prefix='caw-source-selection-') as tmp:
 root=Path(tmp);repo=root/'origin';repo.mkdir();run(['git','init',str(repo)])
 run(['git','config','user.email','test@example.invalid'],repo);run(['git','config','user.name','Offline test'],repo)
 run(['git','config','commit.gpgsign','false'],repo)
 (repo/'client').mkdir();(repo/'client/package.json').write_text('{}\n');run(['git','add','.'],repo);run(['git','commit','-m','reviewed'],repo);first=run(['git','rev-parse','HEAD'],repo)
 (repo/'later').write_text('unreviewed branch update');run(['git','add','.'],repo);run(['git','commit','-m','later'],repo);later=run(['git','rev-parse','HEAD'],repo)
 def check(name,pin,origin=None,target=None,ok=False):
  target=target or root/name;env={**os.environ,'CAW_SOURCE_REPO':str(origin or repo),'CAW_SOURCE_COMMIT':pin}
  proc=subprocess.run(['bash','-c','set -euo pipefail\n'+functions+'\ncaw_select_source "$1"','test',str(target)],env=env,text=True,capture_output=True)
  assert (proc.returncode==0)==ok,(name,proc.stdout,proc.stderr)
  if ok:assert run(['git','rev-parse','HEAD'],target)==pin
  results.append({'case':name,'expected':'accept' if ok else 'reject','exit':proc.returncode})
  return target
 check('missing','');check('branch-name','main');check('malformed','x'*40)
 t=check('selected-old-commit',first,ok=True);assert not (t/'later').exists();assert first!=later
 check('repeat-clean',first,target=t,ok=True)
 (t/'operator-config').write_text('retain me');check('dirty-checkout',first,target=t);assert (t/'operator-config').read_text()=='retain me';assert run(['git','rev-parse','HEAD'],t)==first
 check('unavailable-object','0'*40);check('unavailable-mirror',first,origin=root/'absent')
 plain=root/'plain';plain.mkdir();(plain/'keep').write_text('keep');check('not-a-checkout',first,target=plain);assert (plain/'keep').exists()
 # Full script must refuse a missing pin before any package or service command.
 p=subprocess.run(['bash',str(script)],env={**os.environ,'CAW_SOURCE_COMMIT':''},text=True,capture_output=True)
 assert p.returncode!=0 and 'STOP: set CAW_SOURCE_COMMIT' in p.stderr
 assert '=== CAW node' not in p.stdout
 results.append({'case':'full-installer-early-rejection','expected':'reject','exit':p.returncode})
print(json.dumps({'scope':'offline Git fixtures; no packages installed, services started, node or chain used','cases':results},indent=2))
