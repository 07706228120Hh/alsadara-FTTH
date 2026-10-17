#!/usr/bin/env python3
"""المرحلة 5ب: ألوان Color(0xFFrrggbb) المتبقية → أقرب رمز SdColors من نفس العائلة اللونية.
 - ΔE76 < MAX (افتراضياً 30) + فرق تدرّج اللون (hue) < 35° للألوان المشبعة؛ الرماديات → رماديات/حبر فقط.
 - تُستثنى ملفات الرسوم الفنية والبيانات (EXCLUDE) وألوان العلامات (ذهبي/واتساب).
 - يتجنّب تحويل تدرّج [A, B] إلى لونين متطابقين.
الاستخدام: python3 hex_semantic_codemod.py [--apply] [--max=30] [-v]"""
import os,re,sys,io,json,math
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv; V='-v' in sys.argv
MAX=float(next((a.split('=')[1] for a in sys.argv if a.startswith('--max=')),'30'))
# ألوان علامات تجارية/ميداليات تبقى كما هي (فيسبوك، واتساب، ذهبي/برونزي)
KEEP={'1877F2','075E54','00A884','34B7F1','25D366','128C7E','CD7F32','D4A574','FFD700','FFD200','C0C0C0'}
# تصحيحات يدوية حيث يخطئ Lab في فصل الأزرق عن البنفسجي
OVERRIDE={'1D4ED8':'primaryLight','2563EB':'primarySoft','3D5AFE':'primarySoft'}
EXCLUDE={'pages/login/premium_login_page.dart','network_quality/widgets/depth_3d.dart','pages/kml_zones_map_page.dart'}
tok=dict(re.findall(r'static const (\w+) = Color\(0xFF([0-9A-Fa-f]{6})\)',io.open(os.path.join(LIB,'frontend/tokens/sd_colors.dart'),encoding='utf-8').read()))
SKIPTOK={'whatsapp','whatsappEdge','gold','goldLight','outline','surface','info','infoEdge','infoTint','infoTintEdge','cardEdge','edge','divider'}
tok={k:v for k,v in tok.items() if k not in SKIPTOK}
def lab(h):
    r,g,b=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    f=lambda c: ((c+0.055)/1.055)**2.4 if c>0.04045 else c/12.92
    r,g,b=f(r),f(g),f(b)
    x=(r*0.4124+g*0.3576+b*0.1805)/0.95047; y=r*0.2126+g*0.7152+b*0.0722; z=(r*0.0193+g*0.1192+b*0.9505)/1.08883
    F=lambda t: t**(1/3) if t>0.008856 else 7.787*t+16/116
    return (116*F(y)-16,500*(F(x)-F(y)),200*(F(y)-F(z)))
def ch(L): return math.hypot(L[1],L[2])
def hue(L): return math.degrees(math.atan2(L[2],L[1]))%360
TL={k:lab(v) for k,v in tok.items()}
def ok(L,T):
    c1,c2=ch(L),ch(T)
    if c1<10: return c2<25          # رمادي → رمادي/حبر كحلي
    if c2<10: return False
    dh=abs(hue(L)-hue(T)); dh=min(dh,360-dh)
    return dh<28
def cands(h):
    if h in OVERRIDE: return [(0.0,OVERRIDE[h])]
    L=lab(h); return sorted(((math.dist(L,T),k) for k,T in TL.items() if ok(L,T)))
P=re.compile(r'(?<![A-Za-z0-9_$.])(const\s+)?Color\(0[xX]FF([0-9A-Fa-f]{6})\)')
rep={'files':0,'replaced':0,'left':{},'map':{}}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('frontend/','theme/')) or rel in EXCLUDE: continue
        s=io.open(p,encoding='utf-8').read()
        if 'Color(0x' not in s and 'Color(0X' not in s: continue
        mask=code_mask(s); out=[]; last=0; n=0; prev=None
        for m in P.finditer(s):
            if not mask[m.start()]: continue
            h=m.group(2).upper()
            if h in ('FFFFFF','000000') or h in KEEP: continue
            cs=[c for c in cands(h) if c[0]<MAX]
            # تجنّب تدرّج متطابق: إن كان العنصر السابق مباشرة (بفاصلة) هو نفس الرمز → خذ البديل التالي
            between=s[prev[0]:m.start()] if prev else ''
            if cs and prev and re.fullmatch(r'\s*,\s*(//[^\n]*\n\s*)?',between) and cs[0][1]==prev[1]:
                cs=cs[1:]
            if not cs: rep['left'][h]=rep['left'].get(h,0)+1; prev=None; continue
            t=cs[0][1]; rep['map'][h]=(t,round(cs[0][0],1))
            out.append(s[last:m.start()]); out.append('SdColors.'+t); last=m.end(); n+=1; prev=(m.start()+len('SdColors.'+t) if False else m.end(),t)
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
if V:
    for h,(t,d) in sorted(rep['map'].items(),key=lambda x:x[1][0]): print(' ',h,'→',t,d)
    print('left:',sorted(rep['left'].items(),key=lambda x:-x[1]))
