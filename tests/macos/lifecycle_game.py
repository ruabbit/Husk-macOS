#!/usr/bin/env python3
"""Explicit, silent Minecraft lifecycle/soak checks on an existing session.

Enter a world and verify its screenshot before running. No process is launched,
no window is activated, and all controls use the shipping supervisor protocol.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('session', type=Path)
p.add_argument('--cycles', type=int, default=20)
p.add_argument('--seconds', type=float, default=600)
a = p.parse_args()
if not 0 <= a.cycles <= 100 or not 0 <= a.seconds <= 3600:
    p.error('cycles must be 0..100 and seconds 0..3600')
session = json.loads((a.session/'session.json').read_text())
events = Path(session['logs'])/session['session']/'events.jsonl'
result = {'session': session['session'], 'pid': session['pid'], 'cycles': [], 'samples': [], 'error': None}

def read_events():
    return [json.loads(line) for line in events.read_text().splitlines() if line.strip()]

def send(command, **values):
    with (a.session/'control.jsonl').open('a') as f:
        f.write(json.dumps(dict(command=command, **values))+'\n')

def await_event(predicate, after=0, timeout=30):
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        all_events = read_events()
        if all_events[-1]['state'] in ('failed', 'exited'):
            raise RuntimeError('Runner reached a terminal state during acceptance')
        for event in all_events:
            if event['seq'] > after and predicate(event):
                return event
        time.sleep(.1)
    raise TimeoutError('Expected runner event was not received')

def status():
    after = read_events()[-1]['seq']
    send('status')
    return await_event(lambda e: e['event']=='status', after)

def save():
    (a.session/'lifecycle-result.json').write_text(json.dumps(result, indent=2))

try:
    initial = status()
    assert initial['state']=='running' and not initial['windowVisible'] and not initial['cursorCaptured']
    for cycle in range(a.cycles):
        before = status()
        send('pause')
        ack = await_event(lambda e: e['state']=='paused' and e['event']=='state', before['seq'])
        time.sleep(1)
        first = status()
        time.sleep(2)
        frozen = status()
        assert first['ticks']==frozen['ticks'], 'Graphics continued while paused'
        assert first['audioFrames']==frozen['audioFrames'], 'PCM continued while paused'
        assert frozen['heldKeys']==0 and not frozen['cursorCaptured'], 'Input remained captured'
        send('resume')
        await_event(lambda e: e['state']=='running' and e['event']=='state', frozen['seq'])
        time.sleep(3)
        after = status()
        assert after['ticks']>frozen['ticks'], 'Graphics failed to resume'
        assert after['audioFrames']>frozen['audioFrames'], 'PCM failed to resume'
        result['cycles'].append({'cycle': cycle+1, 'before': before, 'paused': frozen, 'after': after})
        save()
        print(f'PASS pause/resume {cycle+1}/{a.cycles}', flush=True)
    started = time.monotonic()
    start = status()
    while True:
        current = status()
        rss = int(subprocess.check_output(['ps','-o','rss=','-p',str(session['pid'])], text=True).strip())
        result['samples'].append({'seconds': time.monotonic()-started, 'rssKiB': rss,
                                  'frames': current['ticks'], 'audioFrames': current['audioFrames'],
                                  'audioNonzero': current['audioNonzero']})
        assert not current['windowVisible'] and not current['cursorCaptured']
        if len(result['samples'])>1:
            assert current['ticks']>result['samples'][-2]['frames'], 'Render stalled during soak'
            assert current['audioFrames']>result['samples'][-2]['audioFrames'], 'PCM stalled during soak'
        save()
        if time.monotonic()-started >= a.seconds:
            break
        time.sleep(min(5, a.seconds-(time.monotonic()-started)))
    elapsed = time.monotonic()-started
    result['elapsedSeconds'] = elapsed
    result['frames'] = current['ticks']-start['ticks']
    result['fps'] = result['frames']/elapsed
    result['rssMiB'] = {'min': min(x['rssKiB'] for x in result['samples'])/1024,
                        'max': max(x['rssKiB'] for x in result['samples'])/1024}
    result['passed'] = True
except Exception as exc:
    result['passed'] = False
    result['error'] = str(exc)
finally:
    save()
print(json.dumps({k:v for k,v in result.items() if k not in ('cycles','samples')}, ensure_ascii=False), flush=True)
raise SystemExit(0 if result['passed'] else 1)
