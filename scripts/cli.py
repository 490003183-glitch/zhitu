#!/usr/bin/env python3
"""Apple Shortcuts: Run Shell Script; pass tool name then JSON arguments."""
import sys,json
import mcp
if len(sys.argv)<2:
    print('用法: /usr/bin/python3 cli.py list_documents\n或: cli.py --write create_document \'{"title":"新导图"}\'');sys.exit(0)
mcp.WRITE='--write' in sys.argv
args=[x for x in sys.argv[1:] if x!='--write']
try:print(json.dumps(mcp.invoke(args[0],json.loads(args[1]) if len(args)>1 else {}),ensure_ascii=False,indent=2))
except Exception as e:print(str(e),file=sys.stderr);sys.exit(1)
