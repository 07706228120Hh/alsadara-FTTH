"""ماسح Dart بسيط وآمن: يحدد مناطق الكود (خارج النصوص والتعليقات) ويطابق الأقواس."""
import re

def code_mask(s):
    """قائمة منطقية: True لكل حرف من الكود الفعلي (ليس داخل نص أو تعليق)."""
    n=len(s); mask=[True]*n; i=0
    def mark(a,b):
        for k in range(a,min(b,n)): mask[k]=False
    while i<n:
        c=s[i]
        if s.startswith('//',i):
            j=s.find('\n',i); j=n if j<0 else j; mark(i,j); i=j; continue
        if s.startswith('/*',i):
            depth=0; j=i
            while j<n:
                if s.startswith('/*',j): depth+=1; j+=2; continue
                if s.startswith('*/',j):
                    depth-=1; j+=2
                    if depth==0: break
                    continue
                j+=1
            mark(i,j); i=j; continue
        raw=False; st=i
        if c in 'rR' and i+1<n and s[i+1] in '"\'' and (i==0 or not (s[i-1].isalnum() or s[i-1] in '_$')):
            raw=True; i+=1; c=s[i]
        if c in '"\'':
            q=c*3 if s.startswith(c*3,i) else c
            j=i+len(q)
            while j<n:
                if not raw and s[j]=='\\': j+=2; continue
                if s.startswith(q,j): j+=len(q); break
                if len(q)==1 and s[j]=='\n': j+=1; break
                if not raw and s.startswith('${',j):
                    d=0
                    while j<n:
                        if s[j]=='{': d+=1
                        elif s[j]=='}':
                            d-=1
                            if d==0: j+=1; break
                        j+=1
                    continue
                j+=1
            mark(st,j); i=j; continue
        i+=1
    return mask

def match_paren(s,mask,open_idx):
    """فهرس القوس المغلق المطابق لـ s[open_idx]=='(' أو -1."""
    d=0
    for k in range(open_idx,len(s)):
        if not mask[k]: continue
        ch=s[k]
        if ch in '([{': d+=1
        elif ch in ')]}':
            d-=1
            if d==0: return k
    return -1

def top_level_names(args,mask_slice=None):
    """أسماء الوسائط المسماة على المستوى الأعلى (مثل fontSize:)."""
    names=[]; d=0; buf=''
    m=code_mask(args)
    for k,ch in enumerate(args):
        if not m[k]: continue
        if ch in '([{': d+=1
        elif ch in ')]}': d-=1
    for mm in re.finditer(r'(?:^|,)\s*([A-Za-z_]\w*)\s*:',args):
        # تحقق أن الاسم على المستوى الأعلى
        pos=mm.start(1); dd=0
        for k in range(pos):
            if not m[k]: continue
            if args[k] in '([{': dd+=1
            elif args[k] in ')]}': dd-=1
        if dd==0 and m[pos]: names.append(mm.group(1))
    return names
