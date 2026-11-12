from pathlib import Path
import json,urllib.request,concurrent.futures,subprocess,base64,re,hashlib
from Crypto.Hash import keccak
D=Path('work/guppy-recheck-20261111c');D.mkdir(exist_ok=False)
def api(p):return json.loads(subprocess.check_output(['gh','api','repos/QL1-Infinite42-Guppy-Histoire/eth-caw/'+p]))
f=api('contents/index.html');html=base64.b64decode(f['content']).decode();(D/'index.html').write_text(html);(D/'pr.json').write_text(json.dumps(api('pulls/1'),indent=2));(D/'comments.json').write_text(json.dumps(api('issues/1/comments'),indent=2))
urls={'etherscan.io':'https://ethereum.publicnode.com','basescan.org':'https://base.publicnode.com','arbiscan.io':'https://arb1.arbitrum.io/rpc'}
def rpc(url,m,p):
 req=urllib.request.Request(url,json.dumps({'jsonrpc':'2.0','id':1,'method':m,'params':p}).encode(),{'Content-Type':'application/json','User-Agent':'CAW-read-only-review'})
 return json.load(urllib.request.urlopen(req,timeout=25))
def selector(s):return keccak.new(digest_bits=256,data=s.encode()).hexdigest()[:8]
def word(n):return f'{n:064x}'
def check(item):
 host,tx=item;url=urls[host];out={'host':host,'tx':tx,'rpc':url}
 try:
  out['chainId']=rpc(url,'eth_chainId',[]);out['receipt']=rpc(url,'eth_getTransactionReceipt',[tx]);out['transaction']=rpc(url,'eth_getTransactionByHash',[tx]);r=out['receipt']['result'];assert r
  out['block']=rpc(url,'eth_getBlockByNumber',[r['blockNumber'],False]);assert out['block']['result']['hash']==r['blockHash']
  out['readBlock']=rpc(url,'eth_blockNumber',[])['result'];out['owner']=rpc(url,'eth_call',[{'to':r['to'],'data':'0x8da5cb5b'},out['readBlock']])
 except Exception as e:out['error']=str(e)
 (D/(host+'-'+tx+'.json')).write_text(json.dumps(out,indent=2))
 return {'host':host,'tx':tx,'status':out.get('receipt',{}).get('result',{}).get('status'),'to':out.get('receipt',{}).get('result',{}).get('to'),'owner':out.get('owner'),'error':out.get('error')}
items=sorted(set(re.findall(r'https://(etherscan.io|basescan.org|arbiscan.io)/tx/(0x[0-9a-fA-F]{64})',html)))
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:results=list(ex.map(check,items))
print('TRANSACTIONS',json.dumps(results),flush=True)
manager='0x426c22504fd710fbaeacd0c15e7aad80210a1e12';url=urls['etherscan.io'];block=rpc(url,'eth_blockNumber',[])['result'];records=[]
def call(sig,args='',sender=None):
 p={'to':manager,'data':'0x'+selector(sig)+args}
 if sender:p['from']=sender
 x=rpc(url,'eth_call',[p,block]);records.append({'signature':sig,'request':p,'response':x});return x
for n in [1,2]:
 owner=call('getNetworkOwner(uint32)',word(n))['result'];owner='0x'+owner[-40:]
 for s in ['networkFeesLocked(uint32)','networkOwnershipLocked(uint32)','getAuthFee(uint32)','getMintFee(uint32)','getDepositFee(uint32)','getWithdrawFee(uint32)']:call(s,word(n))
 for s,a in [('addAuthorizedSponsor(uint32,address)',word(n)+word(1)),('setGasOverride(uint32,bytes4,uint128)',word(n)+'00'*32+word(1)),('setMintFee(uint32,uint256)',word(n)+word(0))]:
  call(s,a,owner);call(s,a,'0x0000000000000000000000000000000000000002')
cross=[]
for n in [1,2]:
 try:cross.append(rpc('https://rpc.flashbots.net','eth_call',[{'to':manager,'data':'0x'+selector('getNetworkOwner(uint32)')+word(n)},block]))
 except Exception as e:cross.append({'error':str(e)})
out={'block':block,'blockHeader':rpc(url,'eth_getBlockByNumber',[block,False]),'manager':manager,'records':records,'secondProviderOwners':cross};(D/'permissions.json').write_text(json.dumps(out,indent=2))
print('PERMISSIONS',json.dumps({'block':int(block,16),'records':records,'cross':cross}),flush=True)
(D/'PROVENANCE.txt').write_text('\n'.join(f'PARENTS=[public-site,public-RPC] TRANSFORM="read-only transaction and fixed-block authority checks" SHA256={hashlib.sha256(p.read_bytes()).hexdigest()} SIZE={p.stat().st_size} PATH={p.name}'for p in D.iterdir() if p.is_file()))


