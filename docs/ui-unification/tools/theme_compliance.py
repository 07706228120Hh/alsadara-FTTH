#!/usr/bin/env python3
"""فحص التزام الشاشات بالثيم الموحّد (Sd). التشغيل: python3 theme_compliance.py"""
import os,re,json,io,datetime
ROOT=os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib')
ROOT=os.path.abspath(ROOT)
SKIP=('frontend/','theme/','l10n/','generated','.g.dart','.freezed.dart')
MAT=r'Colors\.(red|blue|green|orange|purple|teal|grey|gray|amber|indigo|cyan|pink|yellow|brown|deepOrange|deepPurple|lightBlue|lightGreen|lime|blueGrey)\b'
rows=[]
for dp,_,fs in os.walk(ROOT):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,ROOT).replace('\\','/')
        if any(k in rel for k in SKIP): continue
        s=io.open(p,encoding='utf-8',errors='ignore').read()
        if 'Scaffold(' not in s and 'SdPage(' not in s and 'SdNavShell(' not in s: continue
        code=re.sub(r'//[^\n]*','',s)
        m={
         'lines':s.count('\n')+1,
         'hex':len(re.findall(r'Color\(0x[0-9A-Fa-f]{8}\)',code)),
         'matColors':len(re.findall(MAT,code)),
         'appTheme':len(re.findall(r'\bAppTheme\.',code)),
         'accounting':len(re.findall(r'\bAccountingTheme\.',code)),
         'energy':len(re.findall(r'\bEnergy\w*Theme\.|\bEnergyColors\.',code)),
         'googleFonts':len(re.findall(r'GoogleFonts\.',code)),
         'rawAppBar':len(re.findall(r'(?<![A-Za-z])AppBar\(',code)),
         'rawCard':len(re.findall(r'(?<![A-Za-z])Card\(',code)),
         'styleFrom':len(re.findall(r'\.styleFrom\(',code)),
         'textStyleSize':len(re.findall(r'fontSize:\s*\d',code)),
         'sd':len(re.findall(r'\bSd[A-Z]\w*',code)),
         'sdShell':bool(re.search(r'SdTheme\.scope|SdPage\(|SdNavShell\(',code)),
         'sdAppBar':'SdAppBar(' in code,
        }
        hard=m['hex']+m['matColors']
        legacy=m['appTheme']+m['accounting']+m['energy']+m['googleFonts']
        if m['sd']==0: status='غير مرحّلة'
        elif hard==0 and legacy==0 and m['rawAppBar']==0 and m['styleFrom']==0: status='ملتزمة بالكامل'
        else: status='مرحّلة جزئياً'
        score=m['hex']*2+m['matColors']*2+legacy*1+m['rawAppBar']*5+m['rawCard']*2+m['styleFrom']*3+(0 if m['sdShell'] else 15)
        rows.append(dict(file=rel,module=rel.split('/')[0] if '/' in rel else '(root)',status=status,score=score,**m))
rows.sort(key=lambda r:-r['score'])
tot={k:sum(1 for r in rows if r['status']==k) for k in ['ملتزمة بالكامل','مرحّلة جزئياً','غير مرحّلة']}
out=io.StringIO(); w=out.write
w(f"# تقرير التزام الشاشات بالثيم الموحّد\n\nتاريخ الفحص: {datetime.date.today()} — عدد الشاشات: {len(rows)}\n\n")
w("| الحالة | العدد |\n|---|---|\n"+''.join(f"| {k} | {v} |\n" for k,v in tot.items()))
w(f"\nإجمالي الألوان المكتوبة يدوياً: {sum(r['hex'] for r in rows)} Color(0x..) + {sum(r['matColors'] for r in rows)} Colors.xxx — "
  f"AppTheme: {sum(r['appTheme'] for r in rows)}، AccountingTheme: {sum(r['accounting'] for r in rows)}، Energy: {sum(r['energy'] for r in rows)}، GoogleFonts: {sum(r['googleFonts'] for r in rows)}، AppBar خام: {sum(r['rawAppBar'] for r in rows)}، styleFrom: {sum(r['styleFrom'] for r in rows)}\n\n")
w("## حسب الوحدة\n\n| الوحدة | الشاشات | ملتزمة | جزئية | غير مرحّلة | ألوان يدوية |\n|---|---|---|---|---|---|\n")
mods={}
for r in rows:
    d=mods.setdefault(r['module'],[0,0,0,0,0]); d[0]+=1; d[1+['ملتزمة بالكامل','مرحّلة جزئياً','غير مرحّلة'].index(r['status'])]+=1; d[4]+=r['hex']+r['matColors']
for k,d in sorted(mods.items(),key=lambda x:-x[1][4]): w(f"| {k} | {d[0]} | {d[1]} | {d[2]} | {d[3]} | {d[4]} |\n")
w("\n## كل الشاشات (الأسوأ أولاً)\n\n| # | الملف | الحالة | أسطر | Color(0x) | Colors.x | ثيمات قديمة | AppBar خام | styleFrom | هيكل Sd | نقاط |\n|---|---|---|---|---|---|---|---|---|---|---|\n")
for i,r in enumerate(rows,1):
    leg=r['appTheme']+r['accounting']+r['energy']+r['googleFonts']
    w(f"| {i} | `{r['file']}` | {r['status']} | {r['lines']} | {r['hex']} | {r['matColors']} | {leg} | {r['rawAppBar']} | {r['styleFrom']} | {'✓' if r['sdShell'] else '✗'} | {r['score']} |\n")
w("\n**النقاط** = Color×2 + Colors×2 + ثيمات قديمة + AppBar خام×5 + Card خام×2 + styleFrom×3 + 15 إن لم يُلفّ بـ SdTheme/SdPage/SdNavShell.\n")
open(os.path.join(os.path.dirname(__file__),'../THEME_COMPLIANCE.md'),'w',encoding='utf-8').write(out.getvalue())
json.dump(rows,open(os.path.join(os.path.dirname(__file__),'../theme_compliance.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
print(len(rows),tot)
