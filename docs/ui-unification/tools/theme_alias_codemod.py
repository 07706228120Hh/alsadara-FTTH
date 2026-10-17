#!/usr/bin/env python3
"""يستبدل OldTheme.x بالرمز الموحّد SdColors.y حين يكون x مجرّد اسم بديل (const) للون Sd.
الاستخدام: python3 theme_alias_codemod.py <ملف-الثيم> <اسم-الصنف> [--apply] [--diff]
آمن: يطابق فقط الثوابت اللونية المعرّفة كـ SdColors.* (مباشرة أو عبر سلسلة أسماء)،
يتجاهل النصوص/التعليقات، يضيف import لـ sd_colors بمسار نسبي، ويحذف import الثيم القديم
فقط إن لم يبقَ أي استخدام له في الملف."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
theme_rel,cls=sys.argv[1],sys.argv[2]; APPLY='--apply' in sys.argv
src=io.open(os.path.join(LIB,theme_rel),encoding='utf-8').read()
defs=dict(re.findall(r'static\s+const\s+Color\s+(\w+)\s*=\s*([\w.]+)\s*;',src))
def resolve(n,seen=()):
    v=defs.get(n)
    if v is None or n in seen: return None
    if v.startswith('SdColors.'): return v
    if re.fullmatch(r'\w+',v): return resolve(v,seen+(n,))
    if v.startswith(cls+'.'): return resolve(v.split('.',1)[1],seen+(n,))
    return None
MAP={n:resolve(n) for n in defs}; MAP={k:v for k,v in MAP.items() if v}
PAT=re.compile(r'(?<![A-Za-z0-9_$.])'+cls+r'\.([A-Za-z_]\w*)\b(?!\s*\()')
theme_file=os.path.basename(theme_rel)
rep={'files':0,'replaced':0,'importsAdded':0,'oldImportsRemoved':0,'map':len(MAP)}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel==theme_rel or rel.startswith('frontend/'): continue
        s=io.open(p,encoding='utf-8').read()
        if cls+'.' not in s: continue
        mask=code_mask(s); out=[]; last=0; cnt=0
        for m in PAT.finditer(s):
            if not mask[m.start()] or m.group(1) not in MAP: continue
            out.append(s[last:m.start()]); out.append(MAP[m.group(1)]); last=m.end(); cnt+=1
        if not cnt: continue
        out.append(s[last:]); ns=''.join(out)
        # import sd_colors
        if not re.search(r"^\s*part of\b",ns,re.M) and not re.search(r"import\s+'[^']*frontend/(frontend|tokens/sd_colors)\.dart'",ns):
            relimp=os.path.relpath(os.path.join(LIB,'frontend/tokens/sd_colors.dart'),os.path.dirname(p)).replace('\\','/')
            imps=list(re.finditer(r'^import\s+[^\n]+;\s*$',ns,re.M))
            at=imps[-1].end() if imps else 0
            ns=ns[:at]+"\nimport '"+relimp+"' show SdColors;"+ns[at:]; rep['importsAdded']+=1
        nm=code_mask(ns)
        if not any(nm[x.start()] for x in re.finditer(r'(?<![A-Za-z0-9_$])'+cls+r'\b',ns)):
            ns2=re.sub(r"^import\s+'[^']*"+re.escape(theme_file)+r"'\s*;\s*\n",'',ns,count=1,flags=re.M)
            if ns2!=ns: rep['oldImportsRemoved']+=1; ns=ns2
        rep['files']+=1; rep['replaced']+=cnt
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
        elif '--diff' in sys.argv:
            import difflib; sys.stdout.writelines(list(difflib.unified_diff(s.splitlines(1),ns.splitlines(1),rel,rel,n=0))[:30])
print(json.dumps(rep,ensure_ascii=False))
