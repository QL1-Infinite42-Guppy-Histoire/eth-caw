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
 # Kit adaptation: only the kit-managed overlay paths may differ.
 (t/'operator-config').unlink()
 (t/'client/src/abi').mkdir(parents=True,exist_ok=True)
 (t/'client/src/abi/addresses.ts').write_text('// kit overlay\n')
 (t/'client/config.json').write_text('{}\n')
 check('overlay-only-dirty',first,target=t,ok=True)
 (t/'client/src/abi/addresses.ts').unlink();(t/'client/config.json').unlink()
 # Kit adaptation: an entirely unset commit resolves to the kit default pin.
 env2={k:v for k,v in os.environ.items() if k!='CAW_SOURCE_COMMIT'}
 p2=subprocess.run(['bash','-c','set -euo pipefail\n'+functions+'\ncaw_require_source_selection;echo $CAW_SOURCE_COMMIT'],env=env2,text=True,capture_output=True)
 assert p2.returncode==0 and p2.stdout.strip()=='97cd13f3a1423f702d411472fdd2b2a2e7bfbd59',(p2.stdout,p2.stderr)
 results.append({'case':'default-pin-when-unset','expected':'accept','exit':p2.returncode})
 check('unavailable-object','0'*40);check('unavailable-mirror',first,origin=root/'absent')
 plain=root/'plain';plain.mkdir();(plain/'keep').write_text('keep');check('not-a-checkout',first,target=plain);assert (plain/'keep').exists()
 # Full script must refuse a missing pin before any package or service command.
 p=subprocess.run(['bash',str(script)],env={**os.environ,'CAW_SOURCE_COMMIT':''},text=True,capture_output=True)
 assert p.returncode!=0 and 'STOP: set CAW_SOURCE_COMMIT' in p.stderr
 assert '=== CAW node' not in p.stdout
 results.append({'case':'full-installer-early-rejection','expected':'reject','exit':p.returncode})
print(json.dumps({'scope':'offline Git fixtures; no packages installed, services started, node or chain used','cases':results},indent=2))
