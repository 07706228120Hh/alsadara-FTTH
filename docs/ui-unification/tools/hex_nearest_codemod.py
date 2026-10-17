#!/usr/bin/env python3
"""Color(0xFFrrggbb) المتبقية → أقرب رمز SdColors إذا كان الفرق اللوني ΔE76 < الحد (افتراضياً 10).
الاستخدام: python3 hex_nearest_codemod.py [--apply] [--max=10]"""
import os,re,sys,io,json,math
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv
MAX=float(next((a.split('=')[1] for a in sys.argv if a.startswith('--max=')),'10'))
tok=dict(re.findall(r'static const (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)',io.open(os.path.join(LIB,'frontend/tokens/sd_colors.dart'),encoding='utf-8').read()))
SKIPTOK={'whatsapp','whatsappEdge','gold','goldLight','outline'}
tok={k:v for k,v in tok.items() if k not in SKIPTOK}
def lab(h):
    r,g,b=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    f=lambda c: ((c+0.055)/1.055)**2.4 if c>0.04045 else c/12.92
    r,g,b=f(r),f(g),f(b)
    x=(r*0.4124+g*0.3576+b*0.1805)/0.95047; y=r*0.2126+g*0.7152+b*0.0722; z=(r*0.0193+g*0.1192+b*0.9505)/1.08883
    F=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return (116*F(y)-16,500*(F(x)-F(y)),200*(F(y)-F(z)))
TL={k:lab(v) for k,v in tok.items()}
def nearest(h):
    L=lab(h); best=min(TL.items(),key=lambda kv: math.dist(L,kv[1])); return best[0],math.dist(L,best[1])
P=re.compile(r'(?<![A-Za-z0-9_$.])(const\s+)?Color\(0[xX]FF([0-9A-Fa-f]{6})\)')
rep={'files':0,'replaced':0,'left':{}}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('frontend/','theme/')): continue
        s=io.open(p,encoding='utf-8').read()
        if 'Color(0x' not in s and 'Color(0X' not in s: continue
        mask=code_mask(s); out=[]; last=0; n=0
        for m in P.finditer(s):
            if not mask[m.start()]: continue
            h=m.group(2).upper()
            if h in ('FFFFFF','000000'): continue
            t,d=nearest(h)
            if d<MAX: out.append(s[last:m.start()]); out.append('SdColors.'+t); last=m.end(); n+=1
            else: rep['left'][h]=rep['left'].get(h,0)+1
        if not n: continue
        out.append(s[last:]); ns=''.join(out)
        if not re.search(r'^\s*part of\b',ns,re.M) and not re.search(r"frontend/(frontend|tokens/sd_colors)\.dart",ns):
            relimp=os.path.relpath(os.path.join(LIB,'frontend/tokens/sd_colors.dart'),os.path.dirname(p)).replace('\\','/')
            imps=list(re.finditer(r'^import\s+[^\n]+;[ \t]*(//[^\n]*)?$',ns,re.M)); at=imps[-1].end() if imps else None
            if at is None: continue
            ns=ns[:at]+"\nimport '"+relimp+"' show SdColors;"+ns[at:]
        rep['files']+=1; rep['replaced']+=n
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
print(json.dumps({'files':rep['files'],'replaced':rep['replaced'],'leftTotal':sum(rep['left'].values()),'leftDistinct':len(rep['left'])}))
print(sorted(rep['left'].items(),key=lambda x:-x[1])[:20])
