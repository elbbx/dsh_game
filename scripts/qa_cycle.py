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
    required=['AGENTS.md','doc/GAME_BIBLE.md','doc/独立室内切换与建筑.md','finished/state.json','game/project.godot','game/scenes/main.tscn','game/scripts/Main.gd','game/scripts/SurvivalStats.gd','game/scripts/Consumables.gd','game/data/consumables.json','data/items_original.json','data/recipes_original.json','game/assets/assets_manifest.json','game/tests/PrototypeChecks.gd']
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
    stats_script=(root/'game/scripts/SurvivalStats.gd').read_text('utf8')
    report['checks']['survival_stats']='PASS' if all(t in stats_script for t in ['class_name SurvivalStats','func advance','func _tick','func to_dict','func from_dict','const STEP_SECONDS']) else 'FAIL: missing SurvivalStats API'
    cons_script=(root/'game/scripts/Consumables.gd').read_text('utf8')
    report['checks']['consumables_api']='PASS' if all(t in cons_script for t in ['class_name Consumables','func reload','func consume','func first_for','func inventory_to_dict','func inventory_from_dict']) else 'FAIL: missing Consumables API'
    # Normalized consumables table must be reproducible from the source item data.
    try:
        import re as _re
        src_items=json.loads((root/'data/runtime/items.json').read_text('utf8'))
        hr=_re.compile(r'hunger\s*-\s*(\d+(?:\.\d+)?)'); tr=_re.compile(r'thirst\s*-\s*(\d+(?:\.\d+)?)')
        # 医疗规则原文只给效果类别，按类别映射为保守默认值（派生值，需标 derived）。
        MED={'use MedicalSystem; target injury/infection':{'hp':25.0,'infection':-10.0},
             'body-part bleeding control; action time 2-5s':{'hp':15.0},
             'decrease ZombieInfection; never cure common cold':{'infection':-20.0}}
        expected={}
        for it in src_items:
            rule=it.get('usage_rule_raw') or ''
            eff={}
            if rule in MED:
                eff=dict(MED[rule])
            else:
                m=hr.search(rule)
                if m: eff['hunger']=-float(m.group(1))
                m=tr.search(rule)
                if m: eff['thirst']=-float(m.group(1))
            if eff: expected[it['id']]=(eff, rule in MED)
        tbl=json.loads((root/'game/data/consumables.json').read_text('utf8'))
        assert tbl.get('schema')=='overcastveil.consumables/2', ('schema', tbl.get('schema'))
        got={}
        derived_ok=True
        for e in tbl['items']:
            got[e['id']]=e['effects']
            if e.get('derived'):
                if not e.get('derived_from'):
                    derived_ok=False
            elif e['id'] in expected and expected[e['id']][1]:
                derived_ok=False  # 医疗派生项必须标注 derived
        assert got=={k:v[0] for k,v in expected.items()}, ('table drift', len(got), len(expected))
        assert tbl['count']==len(expected), ('count mismatch', tbl['count'], len(expected))
        assert derived_ok, 'derived flags inconsistent'
        med_n=sum(1 for e in tbl['items'] if e.get('derived'))
        report['checks']['consumables_table']='PASS ('+str(len(expected))+' consumables, '+str(med_n)+' derived medical)'
    except Exception as exc: report['checks']['consumables_table']='FAIL: '+repr(exc)
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
