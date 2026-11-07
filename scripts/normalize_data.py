#!/usr/bin/env python3
"""Convert legacy 578-item/146-recipe tables into typed runtime JSON, preserving original IDs and detecting bad references."""
from pathlib import Path
import json,re,sys,collections

def convert(root:Path)->dict:
    base=root/'data'
    items=json.loads((base/'items_original.json').read_text('utf8'))
    recipes=json.loads((base/'recipes_original.json').read_text('utf8'))
    runtime=base/'runtime'; runtime.mkdir(parents=True,exist_ok=True)
    out_items=[];out_recipes=[];errors=[];warnings=[];item_ids=set();rec_ids=set()
    for row in items:
        id=str(row['id'])
        if id in item_ids:errors.append(f'duplicate item {id}')
        item_ids.add(id)
        size=re.fullmatch(r'([1-9][0-9]*)x([1-9][0-9]*)',str(row.get('grid','')))
        if not size:
            errors.append(f'{id}:invalid grid={row.get("grid")}'); continue
        try:
            kg=float(row.get('weight_kg',0)); stack=int(row.get('stack_max',1))
            if kg<0 or stack<1:raise ValueError
        except (ValueError,TypeError):
            errors.append(f'{id}:invalid weight/stack');continue
        out_items.append({'id':id,'display_name':row.get('name','未命名'),'category':row.get('category','杂项'), 'subcategory':row.get('subcategory',''),
            'weight_kg':kg,'grid_size':[int(size.group(1)),int(size.group(2))],'max_stack':stack,
            'durability_max':int(row.get('durability_max',0) or 0),'base_value':float(row.get('base_value',0) or 0),
            'usage_rule_raw':row.get('usage_effect',''),'access_rule_raw':row.get('access',''),'source_zone':row.get('source_zone',''),'sprite_id':'item_'+id})
    for row in recipes:
        id=str(row['id'])
        if id in rec_ids:errors.append(f'duplicate recipe {id}')
        rec_ids.add(id)
        output=str(row['成品ID'])
        if output not in item_ids:errors.append(f'{id}:missing product {output}')
        ingredients=[]
        for text in str(row.get('材料ID与数量','')).split('|'):
            if not text: continue
            m=re.fullmatch(r'(ITM_\d+):([1-9]\d*)',text)
            if not m:
                errors.append(f'{id}:bad ingredient syntax {text}');continue
            if m.group(1) not in item_ids:errors.append(f'{id}:missing ingredient {m.group(1)}')
            ingredients.append({'item_id':m.group(1),'amount':int(m.group(2))})
        if not ingredients:errors.append(f'{id}:empty ingredients')
        out_recipes.append({'id':id,'product_id':output,'product_amount':int(row.get('数量',1)),
            'ingredients':ingredients,'station_id_raw':row.get('设施',''),'duration_sec':float(row.get('时间秒',0)),
            'skill':row.get('技能',''),'required_level':int(row.get('最低等级',1)),
            'power_wh':float(row.get('耗电Wh',0)), 'operation_text_raw':row.get('操作流程','')})
    if len(out_items)!=len(items):errors.append('some item rows could not be converted')
    # Cycles in recipes may be valid reprocessing chains but cannot be blindly converted to free crafting loops.
    product_to_ings=collections.defaultdict(set)
    for r in out_recipes:product_to_ings[r['product_id']].update(e['item_id'] for e in r['ingredients'])
    for p,ings in product_to_ings.items():
        if p in ings:warnings.append(f'self-referential recipe product {p}')
    (runtime/'items.json').write_text(json.dumps(out_items,indent=2,ensure_ascii=False)+'\n','utf8')
    (runtime/'recipes.json').write_text(json.dumps(out_recipes,indent=2,ensure_ascii=False)+'\n','utf8')
    report={'item_count':len(out_items),'recipe_count':len(out_recipes),'errors':errors,'warnings':warnings,
         'note':'Original natural-language effects and station names retained as *_raw. They must be reviewed and mapped to actual engine rules before enabling the entire catalog.'}
    (runtime/'import_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n','utf8')
    return report

if __name__=='__main__':
    root=Path(__file__).resolve().parent.parent
    if len(sys.argv)>1:root=Path(sys.argv[1]).resolve()
    report=convert(root)
    print('items:',report['item_count'],'recipes:',report['recipe_count'],'errors:',len(report['errors']),'warnings:',len(report['warnings']))
    for err in report['errors'][:15]:print('ERROR:',err)
    sys.exit(1 if report['errors'] else 0)
