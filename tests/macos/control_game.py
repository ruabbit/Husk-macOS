#!/usr/bin/env python3
"""Send opt-in diagnostics to the already running headless acceptance session."""
import argparse
import json
import time
from pathlib import Path

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('session',type=Path)
p.add_argument('action',choices=['tap','touch','key','pause','resume','stop','capture','pad'])
p.add_argument('values',nargs='*')
p.add_argument('--capture')
p.add_argument('--settle',type=float,default=2)
a=p.parse_args()
def send(command,**values):
    with (a.session/'control.jsonl').open('a') as stream:
        stream.write(json.dumps(dict(command=command,**values))+'\n')
if a.action in ('tap','touch'):
    x,y=map(float,a.values)
    if a.action=='tap':
        send('input',source='mouse',action=0,x=x,y=y,buttons=1)
        time.sleep(.12)
        send('input',source='mouse',action=1,x=x,y=y,buttons=0)
    else:
        send('input',source='touch',phase=0,x=x,y=y)
        time.sleep(.12)
        send('input',source='touch',phase=2,x=x,y=y)
elif a.action=='key':
    send('input',source='key',code=int(a.values[0]),down=True)
    time.sleep(min(10,float(a.values[1]) if len(a.values)>1 else .12))
    send('input',source='key',code=int(a.values[0]),down=False)
elif a.action=='pad':
    send('input',source='controller',**json.loads(a.values[0]))
elif a.action=='capture':send('capture',name=a.values[0])
else:send(a.action)
if a.capture:
    time.sleep(max(0,min(30,a.settle)))
    send('capture',name=a.capture)
