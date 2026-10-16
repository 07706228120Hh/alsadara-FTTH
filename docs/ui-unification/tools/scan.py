import os,re,json,sys,collections
root=sys.argv[1]
files=[]
for d,_,fs in os.walk(root):
    for f in fs:
        if f.endswith('.dart'): files.append(os.path.join(d,f))
txt={f:open(f,encoding='utf-8',errors='ignore').read() for f in files}
rel=lambda f: os.path.relpath(f,root)
# import graph
imported=collections.Counter()
for f,s in txt.items():
    for m in re.finditer(r"^import\s+'([^']+)'",s,re.M):
        p=m.group(1)
        if p.startswith('package:alsadara'):
            tgt=os.path.normpath(os.path.join(root,p.split('/',1)[1]))
        elif p.startswith('package:') or p.startswith('dart:'): continue
        else: tgt=os.path.normpath(os.path.join(os.path.dirname(f),p))
        imported[tgt]+=1
    for m in re.finditer(r"^export\s+'([^']+)'",s,re.M):
        tgt=os.path.normpath(os.path.join(os.path.dirname(f),m.group(1))); imported[tgt]+=1
rows=[]
allcolors=collections.Counter()
for f,s in txt.items():
    hexes=re.findall(r'Color\(0x([0-9A-Fa-f]{8})\)',s)
    for h in hexes: allcolors[h.upper()]+=1
    r=dict(file=rel(f),lines=s.count('\n')+1,
      scaffold=s.count('Scaffold('),
      hex=len(hexes), colors_named=len(re.findall(r'\bColors\.[a-z]',s)),
      apptheme=len(re.findall(r'\bAppTheme\.',s)), themeof=s.count('Theme.of('),
      energy=s.count('EnergyDashboardTheme.'), acct=s.count('AccountingTheme.'),
      appbar=s.count('AppBar('), gradient=s.count('LinearGradient('),
      fontsize=len(re.findall(r'fontSize:\s*[0-9]',s)), sp=len(re.findall(r'\.sp\b',s)),
      rtl=s.count('TextDirection.rtl'), withOpacity=s.count('.withOpacity('),
      fontfam=sorted(set(re.findall(r"fontFamily:\s*'([^']+)'",s))),
      imported=imported.get(os.path.normpath(f),0),
      classes=re.findall(r'class (\w+) extends (?:StatefulWidget|StatelessWidget)',s))
    rows.append(r)
json.dump(rows,open('/home/claude/audit/scan.json','w'),ensure_ascii=False)
print(len(rows))
tot=lambda k: sum(r[k] for r in rows)
for k in ['lines','scaffold','hex','colors_named','apptheme','themeof','energy','acct','appbar','gradient','fontsize','sp','withOpacity','rtl']: print(k,tot(k))
print('distinct hex colors',len(allcolors)); print(allcolors.most_common(25))
ff=collections.Counter(x for r in rows for x in r['fontfam']); print(ff)
print('unimported files', sum(1 for r in rows if r['imported']==0))
