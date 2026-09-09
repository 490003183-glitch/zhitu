#!/usr/bin/env python3
"""Local document store shared by the app, CLI and MCP. No network access."""
import os, sys, json, uuid, tempfile, fcntl, base64, re
from pathlib import Path
from contextlib import contextmanager
ROOT = Path(os.environ.get('BRANCH_HOME', str(Path.home() / 'Library/Application Support/枝图')))
def validate(d):
    if d.get('version') not in (1,2): raise ValueError('不支持的工程版本')
    if not re.fullmatch(r'[a-zA-Z0-9-]{1,80}', d.get('id','')): raise ValueError('无效文档 ID')
    if not isinstance(d.get('title'),str): raise ValueError('文档名称必须是文本')
    nodes=d.get('nodes',[])
    if not nodes or len(nodes)>10000: raise ValueError('节点数量必须在 1–10000 之间')
    ids={n['id'] for n in nodes}
    if len(ids)!=len(nodes): raise ValueError('节点 ID 重复')
    by={n['id']:n for n in nodes}
    roots=sum(n.get('parent') is None for n in nodes)
    if roots<1 or (d['version']==1 and roots!=1): raise ValueError('至少保留一个主节点；多主节点工程需要 version 2')
    for n in nodes:
        if not re.fullmatch(r'[a-zA-Z0-9-]{1,80}',n['id']): raise ValueError('无效节点 ID')
        for key in ('notes','tags','link','color','shape','fontFamily','lineStyle'):
            if key in n and not isinstance(n[key],str): raise ValueError(key+' 必须是文本')
        for key,lo,hi in [('fontSize',8,96),('imageSize',60,240)]:
            if key in n and not lo <= float(n[key]) <= hi: raise ValueError(key+' 超出允许范围')
        if not isinstance(n.get('title'),str): raise ValueError('节点标题必须是文本')
        seen=set(); cur=n
        while cur.get('parent') is not None:
            if cur['id'] in seen: raise ValueError('不能形成循环层级')
            seen.add(cur['id'])
            if len(seen)>128: raise ValueError('节点层级超过 128 层')
            if cur['parent'] not in by: raise ValueError('父节点不存在')
            cur=by[cur['parent']]
        if n.get('image'):
            s=n['image']
            if not s.startswith('data:image/jpeg;base64,'): raise ValueError('工程图片必须是 JPG')
            raw=base64.b64decode(s.split(',',1)[1],validate=True)
            if not raw.startswith(b'\xff\xd8\xff') or not raw.endswith(b'\xff\xd9'): raise ValueError('JPG 数据损坏')
    for c in d.get('connections',[]):
        if c.get('from') not in ids or c.get('to') not in ids: raise ValueError('关系线引用不存在的节点')
    return d

def path(docid):
    if not re.fullmatch(r'[a-zA-Z0-9-]{1,80}',docid): raise ValueError('无效文档 ID')
    return ROOT/(docid+'.branch')
@contextmanager
def lock():
    ROOT.mkdir(parents=True,exist_ok=True)
    with open(ROOT/'.lock','a') as f:
        fcntl.flock(f,fcntl.LOCK_EX)
        yield

def atomic(p,data):
    fd,tmp=tempfile.mkstemp(dir=p.parent,prefix='.pending-')
    try:
        with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,p)
        fd=os.open(p.parent,os.O_RDONLY)
        try: os.fsync(fd)
        finally: os.close(fd)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def read(docid):
    p=path(docid)
    try: return validate(json.loads(p.read_text()))
    except Exception as original:
        backup=p.with_suffix('.backup')
        if not backup.exists(): raise original
        d=validate(json.loads(backup.read_text()))
        d['_recovered']=True
        return d

def save(d,expected):
    validate(d); p=path(d['id'])
    with lock():
        old=read(d['id']) if p.exists() else None
        current=old.get('revision',0) if old else 0
        if current!=expected: raise ValueError('版本冲突：工程已由其他窗口或 MCP 修改。请先另存本地副本，再重新载入。')
        if old: atomic(p.with_suffix('.backup'),json.dumps(old,ensure_ascii=False).encode())
        d=dict(d); d.pop('_recovered',None); d['revision']=current+1
        atomic(p,json.dumps(d,ensure_ascii=False).encode())
    return d

def dispatch(a):
    op=a['op']
    if op=='list':
        ROOT.mkdir(parents=True,exist_ok=True); items=[]
        for p in ROOT.glob('*.branch'):
            try:
                d=read(p.stem); items.append({'id':d['id'],'title':d['title'],'revision':d['revision'],'modified':p.stat().st_mtime})
            except Exception: items.append({'id':p.stem,'title':p.stem+'（文件损坏）','revision':-1})
        return sorted(items,key=lambda x:x.get('modified',0),reverse=True)
    if op=='validate': return validate(a['document'])
    if op=='read': return read(a['id'])
    if op=='save': return save(a['document'],a.get('expected',0))
    if op=='import':
        d=validate(a['document']); d['id']=str(uuid.uuid4()); d['revision']=0
        return save(d,0)
    raise ValueError('未知操作')
if __name__=='__main__':
    try: print(json.dumps({'ok':True,'result':dispatch(json.load(sys.stdin))},ensure_ascii=False))
    except Exception as e: print(json.dumps({'ok':False,'error':str(e)},ensure_ascii=False))
