#!/usr/bin/env python3
"""MCP stdio server. Explicit --write enables mutations."""
import sys, json, uuid, argparse, tempfile, subprocess, base64
from pathlib import Path
from store import dispatch,read,save
WRITE='--write' in sys.argv

def schema(props,required=()): return {'type':'object','properties':props,'required':list(required),'additionalProperties':False}
S={'type':'string'}
TOOLS=[
 {'name':'insert_image','description':'从本地 JPG/JPEG 或 PNG 插入图片。PNG 自动白底转 JPG，图片存入工程。需要 --write。','inputSchema':schema({'document_id':S,'node_id':S,'path':S,'expected_revision':{'type':'integer'}},['document_id','node_id','path','expected_revision'])},
 {'name':'list_documents','description':'列出本地枝图文档','inputSchema':schema({})},
 {'name':'read_document','description':'读取完整文档及其 revision','inputSchema':schema({'id':S},['id'])},
 {'name':'create_document','description':'新建本地导图，需要 --write','inputSchema':schema({'title':S},['title'])},
 {'name':'update_document','description':'写入完整文档，必须提交读取时的 expected_revision。工程图片必须是 JPEG data URL。需要 --write。','inputSchema':schema({'document':{'type':'object'},'expected_revision':{'type':'integer'}},['document','expected_revision'])},
 {'name':'edit_node','description':'新增、修改、移动或删除节点及其子树；add_root 在当前画布新建独立主节点，需要 --write。所有修改必须使用最新 expected_revision。','inputSchema':schema({'document_id':S,'expected_revision':{'type':'integer'},'action':{'enum':['add','add_root','edit','move','delete']},'node_id':S,'parent_id':S,'fields':{'type':'object'}},['document_id','expected_revision','action'])}
]
def invoke(name,a):
    if name=='list_documents':return dispatch({'op':'list'})
    if name=='read_document':return read(a['id'])
    if not WRITE:raise ValueError('只读模式：添加 --write 参数才允许修改')
    if name=='create_document':
        d={'version':1,'id':str(uuid.uuid4()),'revision':0,'title':a['title'],'nodes':[{'id':str(uuid.uuid4()),'parent':None,'title':a['title'],'order':0}],'connections':[],'theme':'dark','layout':'horizontal'}
        return save(d,0)
    if name=='update_document':return save(a['document'],a['expected_revision'])
    if name=='insert_image':
        d=read(a['document_id']);n=next((n for n in d['nodes'] if n['id']==a['node_id']),None)
        if n is None:raise ValueError('节点不存在')
        here=Path(__file__).resolve();binary=here.parents[2]/'MacOS/Branch'
        if not binary.exists():binary=here.parents[1]/'build/枝图.app/Contents/MacOS/Branch'
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'image.jpg'
            subprocess.run([str(binary),'--convert-image',str(Path(a['path']).expanduser()),str(out)],check=True,capture_output=True)
            n['image']='data:image/jpeg;base64,'+base64.b64encode(out.read_bytes()).decode();n['imageSize']=150
        return save(d,a['expected_revision'])
    if name=='edit_node':
        d=read(a['document_id']);action=a['action'];n=next((n for n in d['nodes'] if n['id']==a.get('node_id')),None)
        if action=='add_root':
            n={'id':str(uuid.uuid4()),'parent':None,'title':'新主节点','order':sum(x.get('parent') is None for x in d['nodes'])};d['nodes'].append(n);d['version']=2
        elif action=='add':
            parent=a.get('parent_id')
            if not any(x['id']==parent for x in d['nodes']):raise ValueError('父节点不存在')
            n={'id':str(uuid.uuid4()),'parent':parent,'title':'新想法','order':len([x for x in d['nodes'] if x['parent']==parent])};d['nodes'].append(n)
        elif not n:raise ValueError('节点不存在')
        if action in ('add','add_root','edit'):
            fields=a.get('fields',{});allowed={'title','notes','tags','link','color','shape','fontSize','fontFamily','lineStyle','image','imageSize','task','done','collapsed','position'}
            if not set(fields)<=allowed:raise ValueError('包含不支持的节点字段')
            n.update(fields)
        elif action=='move':
            if n['parent'] is None:raise ValueError('不能移动根节点')
            n['parent']=a['parent_id'];n['order']=len([x for x in d['nodes'] if x['parent']==n['parent']])
        elif action=='delete':
            if n['parent'] is None and sum(x.get('parent') is None for x in d['nodes'])<=1:raise ValueError('至少保留一个主节点')
            ids={n['id']}
            while True:
                more={x['id'] for x in d['nodes'] if x.get('parent') in ids}
                if more<=ids:break
                ids|=more
            d['nodes']=[x for x in d['nodes'] if x['id'] not in ids];d['connections']=[c for c in d.get('connections',[]) if c['from'] not in ids and c['to'] not in ids]
        return save(d,a['expected_revision'])
    raise ValueError('未知工具')
def handle(r):
    method=r.get('method');params=r.get('params',{})
    if method=='initialize':return {'protocolVersion':'2025-03-26','capabilities':{'tools':{}},'serverInfo':{'name':'branch-local','version':'0.2.1'}}
    if method=='ping':return {}
    if method=='tools/list':return {'tools':TOOLS}
    if method=='tools/call':
        try:result=invoke(params['name'],params.get('arguments',{}));return {'content':[{'type':'text','text':json.dumps(result,ensure_ascii=False)}]}
        except Exception as e:return {'isError':True,'content':[{'type':'text','text':str(e)}]}
    raise ValueError('未知方法')
def main():
    for line in sys.stdin:
        try:
            r=json.loads(line)
            if 'id' not in r:continue
            try:out={'jsonrpc':'2.0','id':r['id'],'result':handle(r)}
            except Exception as e:out={'jsonrpc':'2.0','id':r['id'],'error':{'code':-32601,'message':str(e)}}
        except Exception as e:out={'jsonrpc':'2.0','id':None,'error':{'code':-32700,'message':str(e)}}
        print(json.dumps(out,ensure_ascii=False),flush=True)
if __name__=='__main__':main()
