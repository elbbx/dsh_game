from pathlib import Path
import csv, json
ROOT=Path(__file__).resolve().parents[2]
def load_csv(name):
    with (ROOT/'03_游戏数据表'/name).open(encoding='utf-8-sig',newline='') as f:
        return list(csv.DictReader(f))
def test_items():
    items=load_csv('物品总表.csv')
    assert len(items)>=350
    assert len({x['id'] for x in items})==len(items)
    assert all(float(x['weight_kg'])>=0 and int(x['stack_max'])>0 for x in items)
    assert len({x['name'] for x in items})==len(items)
def test_recipes():
    item_ids={i['id'] for i in load_csv('物品总表.csv')}
    recipes=load_csv('制作配方总表.csv')
    assert len(recipes)>=100
    for recipe in recipes:
        assert recipe['成品ID'] in item_ids
        assert int(recipe['数量'])>0
        assert int(recipe['时间秒'])>0
        for spec in recipe['材料ID与数量'].split('|'):
            item_id,qty=spec.split(':')
            assert item_id in item_ids and int(qty)>0

def test_buildings():
    base=ROOT/'04_建筑可视化'/'数据源'
    bs=[json.loads(p.read_text(encoding='utf-8')) for p in base.glob('BLD_*.json')]
    assert len(bs)>=35
    for b in bs:
        w,h=b['footprint_m']
        assert len(b['floors'])==b['levels']
        for f in b['floors']:
            assert len(f['rooms'])>=3
            for r in f['rooms']:
                assert r['w']>0 and r['h']>0
                assert 0<=r['x'] and 0<=r['y']
                assert r['x']+r['w']<=w+0.0001 and r['y']+r['h']<=h+0.0001

def test_layers_and_access():
    module=(ROOT/'01_Codex多对话框流程/接口契约.md').read_text(encoding='utf-8')
    for token in ('MAIN_WORLD','INVERTED_WORLD','event_id','M23','M10'):
        assert token in module
    cars=load_csv('载具车型数值.csv')
    assert len(cars)>=18 and all(int(c['座位'])>=1 for c in cars)

if __name__=='__main__':
    for fn in [test_items,test_recipes,test_buildings,test_layers_and_access]:
        fn();print('PASS',fn.__name__)
