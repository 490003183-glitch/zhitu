import unittest,tempfile,sys,os,json,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import store
class StoreTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();store.ROOT=Path(self.tmp.name)
  self.d={'version':1,'id':'test','revision':0,'title':'中文','nodes':[{'id':'r','parent':None,'title':'根'},{'id':'a','parent':'r','title':'子'}],'connections':[]}
 def tearDown(self):self.tmp.cleanup()
 def test_atomic_conflict_recovery(self):
  a=store.save(self.d,0);self.assertEqual(a['revision'],1)
  with self.assertRaisesRegex(ValueError,'版本冲突'):store.save(self.d,0)
  a['title']='第二版';store.save(a,1);store.path('test').write_text('corrupt');self.assertTrue(store.read('test')['_recovered']);self.assertEqual(store.read('test')['title'],'中文')
 def test_invalid_structure_image(self):
  self.d['nodes'][1]['parent']='a'
  with self.assertRaises(ValueError):store.validate(self.d)
  self.d['nodes'][1]['parent']='r';self.d['nodes'][1]['image']='data:image/png;base64,AAAA'
  with self.assertRaisesRegex(ValueError,'JPG'):store.validate(self.d)
 def test_mcp_stdio(self):
  script=Path(__file__).resolve().parents[1]/'scripts/mcp.py';env={**os.environ,'BRANCH_HOME':self.tmp.name}
  req=[{'jsonrpc':'2.0','id':1,'method':'initialize','params':{}},{'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'create_document','arguments':{'title':'测试'}}}]
  def run(write):
   p=subprocess.run([sys.executable,str(script)]+(['--write'] if write else []),input='\n'.join(map(json.dumps,req))+'\n',text=True,capture_output=True,env=env,check=True);return [json.loads(x) for x in p.stdout.splitlines()]
  self.assertTrue(run(False)[1]['result']['isError']);out=run(True);self.assertEqual(out[0]['result']['serverInfo']['name'],'branch-local');self.assertNotIn('isError',out[1]['result']);self.assertEqual(len(store.dispatch({'op':'list'})),1)
 def test_multiple_roots_and_mcp(self):
  import mcp
  original_write=mcp.WRITE;mcp.WRITE=True
  try:
   d=store.save(self.d,0)
   result=mcp.invoke('edit_node',{'document_id':d['id'],'expected_revision':d['revision'],'action':'add_root','fields':{'title':'第二主节点','position':{'x':500,'y':240}}})
   self.assertEqual(result['version'],2)
   roots=[n for n in result['nodes'] if n.get('parent') is None];self.assertEqual(len(roots),2)
   self.assertEqual(store.read(d['id'])['nodes'],result['nodes'])
   bad=dict(result,version=1)
   with self.assertRaises(ValueError):store.validate(bad)
   result=mcp.invoke('edit_node',{'document_id':d['id'],'expected_revision':result['revision'],'action':'delete','node_id':roots[1]['id']})
   self.assertEqual(sum(n.get('parent') is None for n in result['nodes']),1)
   with self.assertRaisesRegex(ValueError,'至少保留'):
    mcp.invoke('edit_node',{'document_id':d['id'],'expected_revision':result['revision'],'action':'delete','node_id':'r'})
  finally:mcp.WRITE=original_write
if __name__=='__main__':unittest.main()
