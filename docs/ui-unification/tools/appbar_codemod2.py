#!/usr/bin/env python3
"""(5ب) يضيف: عنوان Column[Text, Text|if(c) Text] → SdAppBar(title, subtitle).
AppBar(...) البسيطة → SdAppBar(...) (المرحلة 4). يحوّل فقط حين يكون:
 • title: Text(<نص>) بلا وسائط غير style/textAlign/maxLines/overflow/textDirection، و
 • كل الوسائط الأخرى من: actions, leading, automaticallyImplyLeading, bottom, centerTitle,
   backgroundColor, foregroundColor, elevation, iconTheme, surfaceTintColor, shadowColor,
   scrolledUnderElevation, titleTextStyle, toolbarHeight(تُهمل), flexibleSpace(تُهمل إن كانت تدرّجاً).
يُبقي actions/leading/automaticallyImplyLeading/bottom كما هي ويُسقط التنسيق (يأتي من SdAppBar)."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask, match_paren
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv
KEEP={'actions','leading','automaticallyImplyLeading','bottom'}
DROP={'centerTitle','backgroundColor','foregroundColor','elevation','iconTheme','surfaceTintColor','shadowColor','scrolledUnderElevation','titleTextStyle','toolbarHeight','flexibleSpace','actionsIconTheme','systemOverlayStyle','titleSpacing'}
TEXT_OK={'style','textAlign','maxLines','overflow','textDirection','softWrap'}
def split_top(args):
    m=code_mask(args); parts=[]; d=0; st=0
    for i,ch in enumerate(args):
        if not m[i]: continue
        if ch in '([{': d+=1
        elif ch in ')]}': d-=1
        elif ch==',' and d==0: parts.append(args[st:i]); st=i+1
    parts.append(args[st:]); return [p for p in parts if p.strip()]
def named(p):
    mm=re.match(r'\s*([A-Za-z_]\w*)\s*:(.*)\Z',p,re.S); return (mm.group(1),mm.group(2).strip()) if mm else (None,p.strip())
P=re.compile(r'(?<![A-Za-z0-9_$.])(const\s+)?AppBar\(')
rep={'files':0,'converted':0,'skipped':0,'reasons':{}}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('frontend/','theme/')): continue
        s=io.open(p,encoding='utf-8').read()
        if 'AppBar(' not in s: continue
        mask=code_mask(s); out=[]; last=0; n=0
        for m in P.finditer(s):
            if not mask[m.start()] or m.start()<last: continue
            op=m.end()-1; cl=match_paren(s,mask,op)
            if cl<0: continue
            args=split_top(s[op+1:cl]); title=None; keep=[]; ok=True; why=''
            for a in args:
                k,v=named(a)
                if k=='title' and re.match(r'(const\s+)?Column\(',v):
                    cm=re.match(r'(const\s+)?Column\(',v); cargs=split_top(v[cm.end():-1]); kids=None
                    for ca in cargs:
                        ck,cv=named(ca)
                        if ck=='children': kids=cv
                        elif ck not in ('crossAxisAlignment','mainAxisSize','mainAxisAlignment'): kids=None; break
                    if not kids or not kids.startswith('[') or not kids.endswith(']'): ok=False; why='col-kids'; break
                    items=split_top(kids[1:-1])
                    def txt(e):
                        e=e.strip(); tm=re.match(r'(const\s+)?Text\(',e)
                        if not tm or not e.endswith(')'): return None
                        ta=split_top(e[tm.end():-1])
                        if not ta or named(ta[0])[0] is not None or any(named(t)[0] not in TEXT_OK for t in ta[1:]): return None
                        return ta[0].strip()
                    if len(items)!=2: ok=False; why='col-n'; break
                    t1=txt(items[0]); it=items[1].strip(); cond=None
                    im=re.match(r'if\s*\(',it)
                    if im:
                        cp=match_paren(it,code_mask(it),im.end()-1); cond=it[im.end():cp]; it=it[cp+1:]
                    t2=txt(it)
                    if t1 is None or t2 is None: ok=False; why='col-text'; break
                    title=t1; sub=('('+cond+') ? '+t2+' : null') if cond else t2
                    keep.append('subtitle: '+sub)
                elif k=='title':
                    tm=re.match(r'(const\s+)?Text\(',v)
                    if not tm or not v.endswith(')'): ok=False; why='title-not-Text'; break
                    targs=split_top(v[tm.end():-1])
                    if not targs or named(targs[0])[0] is not None: ok=False; why='title-no-pos'; break
                    if any(named(t)[0] not in TEXT_OK for t in targs[1:]): ok=False; why='title-args'; break
                    title=targs[0].strip()
                elif k in KEEP: keep.append(k+': '+v)
                elif k in DROP:
                    if k=='flexibleSpace' and 'gradient' not in v.lower() and 'appBarGradient' not in v: ok=False; why='flexibleSpace'; break
                else: ok=False; why='arg:'+str(k); break
            if not ok or title is None:
                rep['skipped']+=1; w=why or 'no-title'; rep['reasons'][w]=rep['reasons'].get(w,0)+1; continue
            isconst=bool(m.group(1)) and not any(x.startswith('subtitle') for x in keep) and all(re.match(r"^(r?'[^'$]*'|r?\"[^\"$]*\")$",title) for _ in [0])
            new=('const ' if isconst else '')+'SdAppBar(title: '+title+(', '+', '.join(keep) if keep else '')+')'
            out.append(s[last:m.start()]); out.append(new); last=cl+1; n+=1
        if not n: continue
        out.append(s[last:]); ns=''.join(out)
        if not re.search(r'^\s*part of\b',ns,re.M) and not re.search(r"frontend/(frontend|components/sd_app_bar)\.dart",ns):
            relimp=os.path.relpath(os.path.join(LIB,'frontend/components/sd_app_bar.dart'),os.path.dirname(p)).replace('\\','/')
            imps=list(re.finditer(r'^import\s+[^\n]+;[ \t]*(//[^\n]*)?$',ns,re.M))
            if not imps: continue
            at=imps[-1].end(); ns=ns[:at]+"\nimport '"+relimp+"';"+ns[at:]
        rep['files']+=1; rep['converted']+=n
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
        elif '--diff' in sys.argv:
            import difflib; sys.stdout.writelines(list(difflib.unified_diff(s.splitlines(1),ns.splitlines(1),rel,rel,n=0))[:14])
print(json.dumps(rep,ensure_ascii=False))
