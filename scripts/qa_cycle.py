#!/usr/bin/env python3
"""静态核验 + 可选 Godot 无头导入/启动；Godot 不在PATH则严格报告 SKIP。"""
import argparse, json, hashlib, pathlib, shutil, subprocess, sys, datetime, os
import struct

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--root',default='.')
    ap.add_argument('--godot',default='',help='Godot executable explicit path; default finds godot/godot4')
    ap.add_argument('--no-engine',action='store_true')
    args=ap.parse_args()
    root=pathlib.Path(args.root).resolve()
    report={'date_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'root':str(root),'checks':{},'godot':None,'notes':[]}
    required=['AGENTS.md','doc/GAME_BIBLE.md','doc/独立室内切换与建筑.md','finished/state.json','game/project.godot','game/scenes/main.tscn','game/scripts/Main.gd','data/items_original.json','data/recipes_original.json','game/assets/assets_manifest.json','game/tests/PrototypeChecks.gd']
    missing=[i for i in required if not (root/i).exists()]
    report['checks']['required_files']='FAIL: '+str(missing) if missing else 'PASS'
    try:
        items=json.loads((root/'data/items_original.json').read_text('utf8'))
        recipes=json.loads((root/'data/recipes_original.json').read_text('utf8'))
        assert isinstance(items,list) and len(items)==578,(type(items),len(items))
        assert isinstance(recipes,list) and len(recipes)==146,(type(recipes),len(recipes))
        ids=[i['id'] for i in items]
        assert len(set(ids))==len(ids),'duplicate item id'
        report['checks']['legacy_data']='PASS (578 items; 146 recipes)'
    except Exception as exc: report['checks']['legacy_data']='FAIL: '+repr(exc)
    try:
        manifest=json.loads((root/'game/assets/assets_manifest.json').read_text('utf8'))
        assert manifest,'empty asset manifest'
        for item in manifest:
            assert item.get('license') and item.get('id') and item.get('file') and item.get('sha256')
            path=root/'game'/item['file'].replace('res://','')
            assert path.exists(),str(path)
            assert hashlib.sha256(path.read_bytes()).hexdigest()==item['sha256'],str(path)
            header=path.read_bytes()[:26]
            assert header[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
            width,height=struct.unpack('>II',header[16:24])
            assert width>8 and height>8, (width,height)
            assert header[25] == 6, 'not RGBA PNG' 
        report['checks']['asset_manifest']='PASS ('+str(len(manifest))+' original PNGs)'
    except Exception as exc: report['checks']['asset_manifest']='FAIL: '+repr(exc)
    bad=[str(p.relative_to(root)) for p in (root/'game').rglob('*') if p.is_file() and p.suffix.lower() in {'.glb','.gltf','.fbx','.blend','.obj','.vox','.bbmodel','.stl','.dae'}]
    report['checks']['no_3d_models']='FAIL: '+str(bad) if bad else 'PASS'
    script=(root/'game/scripts/Main.gd').read_text('utf8')
    report['checks']['prototype_features']='PASS' if all(t in script for t in ['func _transition','func _save_game','func _load_game','func _reset_run','func cell_to_screen','func _attack','func _process_zombies']) else 'FAIL: missing core functions'
    godot=args.godot or shutil.which('godot') or shutil.which('godot4')
    if args.no_engine or not godot:
        report['checks']['godot_import']='SKIP: no engine requested' if args.no_engine else 'SKIP: Godot executable not found'
        report['checks']['godot_smoke']='SKIP: no engine requested' if args.no_engine else 'SKIP: Godot executable not found'
        report['checks']['godot_gameplay']='SKIP: no engine requested' if args.no_engine else 'SKIP: Godot executable not found'
    else:
        # Godot on Windows may emit bytes outside the console codepage. Force
        # UTF-8 with replacement so a decode error never turns a real engine
        # result into a NoneType crash that masquerades as a QA failure.
        PIPE_KW = dict(capture_output=True, text=True, encoding='utf-8', errors='replace')
        try:
            ver = subprocess.run([godot,'--version'], timeout=20, **PIPE_KW)
            report['godot'] = (ver.stdout or ver.stderr or '').strip()
            for name,command in [ ('godot_import',[godot,'--headless','--path',str(root/'game'),'--editor','--quit']),('godot_smoke',[godot,'--headless','--path',str(root/'game'),'--quit-after','120']),('godot_gameplay',[godot,'--headless','--path',str(root/'game'),'--script','res://tests/PrototypeChecks.gd']) ]:
                result=subprocess.run(command, timeout=80, **PIPE_KW)
                output=((result.stdout or '')+'\n'+(result.stderr or ''))[-13000:]
                errors=['SCRIPT ERROR','Parse Error','ERROR: Failed loading','ERROR: Cannot open','ERROR: Cannot parse']
                if result.returncode==0 and not any(e in output for e in errors) and (name!='godot_gameplay' or 'TEST_PASS:' in output):
                    report['checks'][name]='PASS'
                else:
                    report['checks'][name]='FAIL: exit code '+str(result.returncode)
                report[name+'_log']=output
        except Exception as exc:
            report['checks']['godot_import']='FAIL: '+repr(exc)
            report['checks']['godot_smoke']='SKIP: failed to invoke engine'
            report['checks']['godot_gameplay']='SKIP: failed to invoke engine'
    dest=root/'finished'/'reports'
    dest.mkdir(exist_ok=True,parents=True)
    out=dest/('qa_'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.json')
    out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    for k,v in report['checks'].items():print(f'{k}: {v}')
    print('report:',out)
    failures=any(v.startswith('FAIL') for v in report['checks'].values())
    return 1 if failures else 0

if __name__=='__main__': sys.exit(main())
