#!/usr/bin/env python3
"""المرحلة 2ب: AccountingTheme → SdUiKit و EnergyDashboardTheme → SdDashKit (نُقلتا إلى lib/frontend/components).
يستبدل الاسم في الكود فقط، ويبدّل import الثيم القديم بـ import الأداة الجديدة (أو يكتفي بالـ barrel إن وُجد)."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv
RULES=[('AccountingTheme','SdUiKit','accounting_theme.dart','sd_ui_kit.dart'),('EnergyDashboardTheme','SdDashKit','energy_dashboard_theme.dart','sd_dash_kit.dart')]
rep={'files':0,'replaced':0}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('theme/','frontend/')): continue
        s=io.open(p,encoding='utf-8').read(); ns=s; touched=False
        for old,new,oldfile,newfile in RULES:
            if old not in ns: continue
            mask=code_mask(ns); out=[]; last=0; n=0
            for m in re.finditer(r'(?<![A-Za-z0-9_$])'+old+r'\b',ns):
                if not mask[m.start()]: continue
                out.append(ns[last:m.start()]); out.append(new); last=m.end(); n+=1
            if not n: continue
            out.append(ns[last:]); ns=''.join(out); rep['replaced']+=n; touched=True
            ns=re.sub(r"^import\s+'[^']*"+re.escape(oldfile)+r"'\s*;[ \t]*\n",'',ns,count=1,flags=re.M)
            ispart=re.search(r'^\s*part of\b',ns,re.M)
            if not ispart and not re.search(r"frontend/(frontend|components/"+re.escape(newfile)+r")'",ns):
                relimp=os.path.relpath(os.path.join(LIB,'frontend/components/'+newfile),os.path.dirname(p)).replace('\\','/')
                imps=list(re.finditer(r'^import\s+[^\n]+;[ \t]*$',ns,re.M)); at=imps[-1].end() if imps else 0
                ns=ns[:at]+"\nimport '"+relimp+"';"+ns[at:]
        if not touched: continue
        # themes.dart: احذفه إن لم يعد AppTheme مستخدماً
        if "themes.dart'" in ns:
            m2=code_mask(ns)
            if not any(m2[x.start()] for x in re.finditer(r'(?<![A-Za-z0-9_$])AppTheme\b',ns)):
                ns=re.sub(r"^import\s+'[^']*theme/themes\.dart'\s*;[ \t]*\n",'',ns,count=1,flags=re.M)
        rep['files']+=1
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
print(json.dumps(rep))
