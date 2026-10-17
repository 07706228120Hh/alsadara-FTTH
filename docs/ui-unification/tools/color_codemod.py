#!/usr/bin/env python3
"""تحويل الألوان اليدوية إلى رموز SdColors بجدول دلالي (المرحلة 3 من THEME_CLEANUP_PLAN).
الاستخدام: python3 color_codemod.py [--apply] [--diff] [بادئة-مسار ...]
قواعد الأمان:
 • يتجاهل النصوص والتعليقات وملفات frontend/ و theme/.
 • Colors.x.shadeN و Colors.x[N] (مع ! إن وُجد) تُحوَّل دائماً (نوعها Color أصلاً).
 • Colors.x المجرّدة (نوعها MaterialColor) لا تُحوَّل في الملفات التي تحوي MaterialColor/primarySwatch
   أو تستخدم .shadeN / [N] على متغيرات — لتجنّب كسر الأنواع.
 • Color(0x..) تُحوَّل فقط إن كانت في الجدول الصريح؛ غير ذلك يُترك ويُذكر في التقرير.
 • Colors.white / black / transparent لا تُلمس."""
import os,re,sys,io,json
sys.path.insert(0,os.path.dirname(__file__))
from dart_scan import code_mask
LIB=os.path.abspath(os.path.join(os.path.dirname(__file__),'../../../src/Apps/CompanyDesktop/alsadara-ftth/lib'))
APPLY='--apply' in sys.argv; FILTERS=[a for a in sys.argv[1:] if not a.startswith('--')]
S='SdColors.'
FAM={ # base, edge, tint, tintEdge, light
 'danger':('danger','dangerEdge','dangerTint','dangerTintEdge','danger'),
 'success':('success','successEdge','successTint','successTintEdge','success'),
 'warning':('warning','warningEdge','warningTint','warningTintEdge','warning'),
 'info':('info','infoEdge','infoTint','infoTintEdge','info'),
 'primary':('primary','primaryEdge','primaryTint','primaryTintEdge','primaryLight'),
 'accent':('accent','accentEdge','accentTint','accentTintEdge','accentLight'),
 'platform':('platformBase','platformEdge','platformTint','platformTintEdge','platformLight'),
}
MAT={'red':'danger','green':'success','lightGreen':'success','lime':'success','orange':'warning','amber':'warning',
     'deepOrange':'warning','yellow':'warning','brown':'warning','blue':'info','lightBlue':'info','indigo':'primary',
     'teal':'accent','cyan':'accent','purple':'platform','deepPurple':'platform','pink':'platform'}
GREY={'50':'surfaceAlt','100':'groundAlt','200':'divider','300':'edge','400':'faint','500':'faint','600':'muted','700':'muted','800':'ink','900':'ink'}
def mat_token(name,shade):
    if name in ('grey','blueGrey'): return S+GREY.get(shade or '500','faint')
    b,e,t,te,l=FAM[MAT[name]]
    if shade in ('50','100'): return S+t
    if shade in ('200','300'): return S+te
    if shade=='400': return S+l
    if shade=='900': return S+e
    return S+b
HEX={ # لون → رمز (مطابقة دلالية مقصودة)
 '1A237E':'primary','283593':'primaryMid','3949AB':'primaryLight','5C6BC0':'primarySoft','1E3A5F':'primaryEdge',
 '3498DB':'info','1565C0':'info','1976D2':'info','2196F3':'info','1E88E5':'info','2980B9':'info','3B82F6':'info','64B5F6':'infoTintEdge',
 '2E7D32':'success','4CAF50':'success','27AE60':'success','43A047':'success','2ECC71':'success','22C55E':'success','10B981':'success','1B5E20':'successEdge','E8F5E9':'successTint',
 'E74C3C':'danger','C62828':'danger','EF4444':'danger','F44336':'danger','E53935':'danger','FF5252':'danger',
 'FF9800':'warning','EF6C00':'warning','F39C12':'warning','E65100':'warningEdge','E67E22':'warning','F9A825':'warning','F59E0B':'warning','FFF3E0':'warningTint','FFE0B2':'warningTintEdge',
 '8E44AD':'platformBase','9C27B0':'platformBase','6A1B9A':'platformBase','9B59B6':'platformBase','4A148C':'platformEdge','764BA2':'platformBase',
 '00695C':'accent','00897B':'accent','009688':'accent','1ABC9C':'accent','16A085':'accent','80DEEA':'accentTintEdge',
 '667EEA':'primaryLight',
 '2C3E50':'ink','1A1A2E':'ink','1E293B':'ink','475569':'muted','64748B':'muted','95A5A6':'faint','607D8B':'muted',
 'E0E6ED':'divider','E2E8F0':'divider','DDDDDD':'edge','EEEEEE':'divider','F8F9FA':'surfaceAlt','F5F7FA':'surfaceAlt','F8FAFE':'surfaceAlt','F5F6FA':'surfaceAlt',
 '25D366':'whatsapp','128C7E':'whatsappEdge',
}
P_SHADE=re.compile(r'(?<![A-Za-z0-9_$.])(const\s+)?Colors\.(red|green|lightGreen|lime|orange|amber|deepOrange|yellow|brown|blue|lightBlue|indigo|teal|cyan|purple|deepPurple|pink|grey|blueGrey)(?:\.shade(\d+)|\[(\d+)\](!)?)')
P_BARE=re.compile(r'(?<![A-Za-z0-9_$.])Colors\.(red|green|lightGreen|lime|orange|amber|deepOrange|yellow|brown|blue|lightBlue|indigo|teal|cyan|purple|deepPurple|pink|grey|blueGrey)\b(?!\s*\.\s*shade|\s*\[|\s*\.\s*(?!withOpacity|withValues|withAlpha)[A-Za-z])')
P_HEX=re.compile(r'(?<![A-Za-z0-9_$.])(const\s+)?Color\(0[xX]FF([0-9A-Fa-f]{6})\)')
RISKY=re.compile(r'MaterialColor|primarySwatch|ColorSwatch|(?<!Colors\.)(?<![A-Za-z])[a-z_]\w*\.shade\d|(?<![A-Za-z.])[a-z_]\w*\[(?:50|[1-9]00)\]')
rep={'files':0,'shade':0,'bare':0,'hex':0,'bareSkippedFiles':[],'hexLeft':{}}
for dp,_,fs in os.walk(LIB):
    for f in fs:
        if not f.endswith('.dart'): continue
        p=os.path.join(dp,f); rel=os.path.relpath(p,LIB).replace('\\','/')
        if rel.startswith(('frontend/','theme/')) or rel.endswith(('.g.dart','.freezed.dart')): continue
        if FILTERS and not any(rel.startswith(x) for x in FILTERS): continue
        s=io.open(p,encoding='utf-8').read()
        if 'Colors.' not in s and 'Color(0x' not in s and 'Color(0X' not in s: continue
        mask=code_mask(s)
        code_only=''.join(ch if mask[i] else ' ' for i,ch in enumerate(s))
        risky=bool(RISKY.search(code_only))
        edits=[]
        for m in P_SHADE.finditer(s):
            if mask[m.start()]: edits.append((m.start(),m.end(),mat_token(m.group(2),m.group(3) or m.group(4)),'shade'))
        if not risky:
            for m in P_BARE.finditer(s):
                if mask[m.start()]: edits.append((m.start(),m.end(),mat_token(m.group(1),None),'bare'))
        elif P_BARE.search(code_only): rep['bareSkippedFiles'].append(rel)
        for m in P_HEX.finditer(s):
            if not mask[m.start()]: continue
            h=m.group(2).upper()
            if h in HEX: edits.append((m.start(),m.end(),S+HEX[h],'hex'))
            else: rep['hexLeft'][h]=rep['hexLeft'].get(h,0)+1
        if not edits: continue
        edits.sort(); out=[]; last=0; n=0
        for a,b,t,k in edits:
            if a<last: continue
            out.append(s[last:a]); out.append(t); last=b; rep[k]+=1; n+=1
        out.append(s[last:]); ns=''.join(out)
        if not re.search(r"^\s*part of\b",ns,re.M) and not re.search(r"frontend/(frontend|tokens/sd_colors)\.dart",ns):
            relimp=os.path.relpath(os.path.join(LIB,'frontend/tokens/sd_colors.dart'),os.path.dirname(p)).replace('\\','/')
            imps=list(re.finditer(r'^import\s+[^\n]+;[ \t]*$',ns,re.M))
            at=imps[-1].end() if imps else 0
            ns=ns[:at]+"\nimport '"+relimp+"' show SdColors;"+ns[at:]
        rep['files']+=1
        if APPLY: io.open(p,'w',encoding='utf-8').write(ns)
        elif '--diff' in sys.argv:
            import difflib; sys.stdout.writelines(list(difflib.unified_diff(s.splitlines(1),ns.splitlines(1),rel,rel,n=0))[:24])
top=sorted(rep['hexLeft'].items(),key=lambda x:-x[1])[:25]
print(json.dumps({'files':rep['files'],'shade':rep['shade'],'bare':rep['bare'],'hex':rep['hex'],'bareSkippedFiles':len(rep['bareSkippedFiles']),'hexLeftTotal':sum(rep['hexLeft'].values())},ensure_ascii=False))
print('bare skipped in:',rep['bareSkippedFiles'][:30]); print('hex left top:',top)
