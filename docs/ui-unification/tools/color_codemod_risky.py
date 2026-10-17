#!/usr/bin/env python3
"""Colors.<لون> المجرّدة في الملفات التي تستخدم MaterialColor — تحويل انتقائي آمن:
 يُحوَّل الاستخدام فقط إن كان قيمة لوسيط مسمّى من نوع Color في ودجات Flutter (color:, backgroundColor: …)
 وليس داخل استدعاء دالة/صنف في نفس الملف يصرّح بمعامل MaterialColor."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
from color_codemod import mat_token, RISKY  # noqa
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv
NAMES='color|backgroundColor|foregroundColor|iconColor|borderColor|fillColor|focusColor|hoverColor|splashColor|highlightColor|shadowColor|surfaceTintColor|selectedColor|disabledColor|activeColor|inactiveColor|thumbColor|trackColor|checkColor|indicatorColor|labelColor|unselectedLabelColor|dividerColor|cursorColor|selectedItemColor|unselectedItemColor|valueColor|decorationColor|textColor|barrierColor'
P=re.compile(r'(?<![A-Za-z0-9_$])(?:'+NAMES+r')\s*:\s*(Colors\.(red|green|lightGreen|lime|orange|amber|deepOrange|yellow|brown|blue|lightBlue|indigo|teal|cyan|purple|deepPurple|pink|grey|blueGrey))(?=\s*[,)\]}])')
rep={'files':0,'replaced':0,'skippedHelper':0}
SK={}; CALLS={}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('frontend/','theme/')): continue
        s=io.open(p,encoding='utf-8').read(); mask=code_mask(s)
        code=''.join(ch if mask[i] else ' ' for i,ch in enumerate(s))
        if not RISKY.search(code): continue
        helpers=set()
        for mc in re.finditer(r'\bMaterialColor\b',code):
            d=0; k=mc.start()-1
            while k>=0:
                ch=code[k]
                if ch in ')]}': d+=1
                elif ch in '([{':
                    if d==0:
                        if ch=='{' and k>0 and code[k-1]=='(' : k-=1; ch='('
                        if ch=='(':
                            mm=re.search(r'([A-Za-z_]\w*)\s*(?:<[^()]*>)?\s*$',code[max(0,k-120):k])
                            if mm: helpers.add(mm.group(1))
                        break
                    d-=1
                k-=1
        # كل الدوال المعرّفة في الملف (للتقرير) — الاستدعاءات بدون اسم (records/maps) تُتخطّى
        for cm in re.finditer(r'class\s+(\w+)[^{]*\{',code):
            body=code[cm.end():cm.end()+4000]
            if re.search(r'\bMaterialColor\b',body.split('\nclass ')[0]): helpers.add(cm.group(1))
        out=[]; last=0; n=0
        for m in P.finditer(s):
            a=m.start(1)
            if not mask[a]: continue
            # أقرب قوس مفتوح غير مغلق قبل الموضع → اسم الاستدعاء
            d=0; k=a-1; call=None
            while k>=0:
                if mask[k]:
                    ch=s[k]
                    if ch in ')]}': d+=1
                    elif ch in '([{':
                        if d==0:
                            if ch=='(':
                                mm=re.search(r'([A-Za-z_]\w*)\s*$',s[max(0,k-80):k]); call=mm.group(1) if mm else None
                            break
                        d-=1
                k-=1
            if call is None or call in helpers: rep['skippedHelper']+=1; SK.setdefault(rel,set()).add(str(call)); continue
            CALLS.setdefault(call,0); CALLS[call]+=1
            out.append(s[last:a]); out.append(mat_token(m.group(2),None)); last=m.end(1); n+=1
        if not n: continue
        out.append(s[last:]); ns=''.join(out)
        rep['files']+=1; rep['replaced']+=n
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
print(json.dumps(rep))
if '-v' in sys.argv:
    print({k:sorted(v) for k,v in SK.items()})
    print(sorted(CALLS.items(),key=lambda x:-x[1]))
