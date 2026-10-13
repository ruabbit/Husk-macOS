#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import sys
import zipfile

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[2]) as source:
    manifest = source.read('AndroidManifest.xml')
page = '''<!doctype html><meta charset="utf-8"><title>Husk Web Fixture</title>
<button id="button" onclick="document.querySelector('#value').textContent='clicked'">Click</button>
<input id="text"><p id="value">ready</p><script>
window.responses=[];
window.Capacitor=window.Capacitor || {};
window.Capacitor.fromNative=function (message) { responses.push(message); };
window.database=function(){return new Promise(function(resolve,reject){
 const r=indexedDB.open('husk-fixture',1);r.onupgradeneeded=()=>r.result.createObjectStore('save');
 r.onerror=()=>reject(r.error);r.onsuccess=()=>resolve(r.result);
});};
window.persist=async function(value){
 localStorage.setItem('save',value);document.cookie='husk='+value+'; max-age=86400; path=/';
 const db=await database();await new Promise((resolve,reject)=>{const t=db.transaction('save','readwrite');t.objectStore('save').put(value,'key');t.oncomplete=resolve;t.onerror=()=>reject(t.error);});db.close();return true;
};
window.readSave=async function(){
 const db=await database();const value=await new Promise((resolve,reject)=>{const r=db.transaction('save').objectStore('save').get('key');r.onsuccess=()=>resolve(r.result || null);r.onerror=()=>reject(r.error);});db.close();return {local:localStorage.getItem('save'),indexed:value,cookie:document.cookie};
};
window.fixtureReady=true;
</script>'''
for kind in ['capacitor','cordova']:
    folder = 'public' if kind == 'capacitor' else 'www'
    with zipfile.ZipFile(out/f'{kind}.apk','w',zipfile.ZIP_DEFLATED) as apk:
        apk.writestr('AndroidManifest.xml',manifest)
        apk.writestr(f'assets/{folder}/index.html',page)
        if kind == 'capacitor': apk.writestr('assets/capacitor.config.json',json.dumps({'appId':'org.husk.driver'}))
        else: apk.writestr('assets/www/cordova.js','// fixture bridge marker')
print('Prepared isolated Capacitor and Cordova applications')
