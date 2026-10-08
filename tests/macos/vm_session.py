#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bounded, silent real-VM supervisor. Append JSON commands to control.jsonl."""
import argparse
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import threading
import time
import uuid

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runner',type=Path,required=True)
    p.add_argument('--guest',type=Path,required=True)
    p.add_argument('--session-dir',type=Path,required=True)
    p.add_argument('--accelerator',choices=['tcg','hvf'],default='tcg')
    p.add_argument('--graphics',choices=['software','virgl'],default='virgl')
    p.add_argument('--seconds',type=int,default=1200)
    p.add_argument('--width',type=int,default=960)
    p.add_argument('--height',type=int,default=540)
    a=p.parse_args();d=a.session_dir.resolve();d.mkdir(parents=True,exist_ok=False)
    config={'session':str(uuid.uuid4()),'guest':str(a.guest.resolve()),'accelerator':a.accelerator,
            'graphics':a.graphics,'memoryMiB':4096,'cpus':4,'width':a.width,'height':a.height,
            'showWindow':False,'muted':True,'automation':True,'maxRunSeconds':a.seconds}
    (d/'config.json').write_text(json.dumps(config,indent=2)+'\n');(d/'control.jsonl').touch()
    log=(d/'stderr.log').open('wb');events=(d/'events.jsonl').open('w');samples=(d/'samples.jsonl').open('w')
    child=subprocess.Popen([str(a.runner.resolve()),'--config',str(d/'config.json')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,bufsize=0)
    (d/'pid').write_text(str(child.pid)+'\n');incoming=queue.Queue();stop=False
    def read():
        for line in child.stdout:incoming.put(line)
        incoming.put(None)
    threading.Thread(target=read,daemon=True).start()
    def interrupt(*_):
        nonlocal stop
        stop=True
    signal.signal(signal.SIGTERM,interrupt);signal.signal(signal.SIGINT,interrupt)
    start=time.monotonic();next_sample=start;request=0;deadline=None
    def send(command):
        nonlocal request
        request+=1;command={'session':config['session'],'id':request,**command}
        child.stdin.write((json.dumps(command)+'\n').encode());child.stdin.flush()
        return request
    print(json.dumps({'pid':child.pid,'session':config['session'],'directory':str(d)}),flush=True)
    with (d/'control.jsonl').open() as control:
        while child.poll() is None:
            while not incoming.empty():
                line=incoming.get()
                if line is None:break
                events.write(line.decode(errors='replace'));events.flush()
                try:
                    e=json.loads(line)
                    if e.get('event')!='heartbeat':print(json.dumps(e,ensure_ascii=False),flush=True)
                except json.JSONDecodeError:print('Non-JSON runner output',line[:200],flush=True)
            line=control.readline()
            if line:
                try:
                    command=json.loads(line);send(command)
                    if command.get('command')=='shutdown' and deadline is None:deadline=time.monotonic()+55
                except Exception as e:print('Command failed:',e,flush=True)
            if time.monotonic()>=next_sample:
                rss=subprocess.run(['ps','-o','rss=','-p',str(child.pid)],capture_output=True,text=True).stdout.strip()
                samples.write(json.dumps({'elapsed':time.monotonic()-start,'rssKiB':int(rss) if rss else None})+'\n');samples.flush();next_sample+=5
            if (stop or time.monotonic()-start>a.seconds+5) and deadline is None:
                try:send({'command':'shutdown'})
                except BrokenPipeError:pass
                deadline=time.monotonic()+55
            if deadline and time.monotonic()>deadline:
                child.kill();break
            time.sleep(.1)
    rc=child.wait();time.sleep(.1)
    while not incoming.empty():
        line=incoming.get()
        if line:events.write(line.decode(errors='replace'))
    events.close();log.close();samples.close()
    result={'exitCode':rc,'elapsed':time.monotonic()-start,'pid':child.pid,'reaped':True}
    (d/'result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
    return rc

if __name__=='__main__':raise SystemExit(main())
