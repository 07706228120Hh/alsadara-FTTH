#!/usr/bin/env python3
"""GoogleFonts.cairo(...) → TextStyle(fontFamily: 'Cairo', ...) — نفس الوسائط حرفياً.
الاستخدام: python3 fonts_codemod.py [--apply] [مسار-جزئي ...]
بدون --apply: تقرير فقط. يتجاهل النصوص والتعليقات، ويترك textStyle: للمراجعة اليدوية."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask, match_paren, top_level_names
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv; FILTERS=[a for a in sys.argv[1:] if not a.startswith('--')]
PAT=re.compile(r'(?<![A-Za-z0-9_$.])GoogleFonts\.cairo\(')
IMPORT=re.compile(r"^import\s+'package:google_fonts/google_fonts\.dart';\s*\n",re.M)
report={'files':0,'replaced':0,'skipped':[],'importsRemoved':0}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if FILTERS and not any(rel.startswith(x) for x in FILTERS): continue
        s=io.open(p,encoding='utf-8').read()
        if 'GoogleFonts' not in s: continue
        mask=code_mask(s); out=[]; last=0; cnt=0
        for m in PAT.finditer(s):
            if not mask[m.start()] or m.start()<last: continue
            op=m.end()-1; cl=match_paren(s,mask,op)
            if cl<0: report['skipped'].append((rel,s.count('\n',0,m.start())+1,'unbalanced')); continue
            args=s[op+1:cl]
            if 'textStyle' in top_level_names(args):
                report['skipped'].append((rel,s.count('\n',0,m.start())+1,'textStyle')); continue
            body=args.strip()
            if not body: new="TextStyle(fontFamily: 'Cairo')"
            else:
                lead=args[:len(args)-len(args.lstrip())]
                sep=lead if '\n' in lead else ' '
                new="TextStyle("+lead+"fontFamily: 'Cairo',"+sep+args.lstrip()+")"
            out.append(s[last:m.start()]); out.append(new); last=cl+1; cnt+=1
        if not cnt: continue
        out.append(s[last:]); ns=''.join(out)
        nm=code_mask(ns)
        still=any(nm[x.start()] for x in re.finditer(r'(?<![A-Za-z0-9_$])GoogleFonts\.',ns))
        if not still and IMPORT.search(ns): ns=IMPORT.sub('',ns,count=1); report['importsRemoved']+=1
        report['files']+=1; report['replaced']+=cnt
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
        elif '--diff' in sys.argv:
            import difflib; sys.stdout.writelines(list(difflib.unified_diff(s.splitlines(1),ns.splitlines(1),rel,rel,n=1))[:60])
print(json.dumps({k:(v if k!='skipped' else len(v)) for k,v in report.items()},ensure_ascii=False))
for x in report['skipped'][:40]: print('SKIP',*x)
