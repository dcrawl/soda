#!/usr/bin/env python3
# analyze_trace.py tp.xml -- self-time by symbol and by bucket from an xctrace time-profile export.
import sys, collections, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
ids = {}
def res(e):
    r = e.get('ref')
    if r is not None: return ids[r]
    if e.get('id') is not None: ids[e.get('id')] = e
    return e
selfc = collections.Counter(); incl = collections.Counter(); tot = 0
for row in root.iter('row'):
    for ch in row: 
        if ch.get('id') is not None: ids[ch.get('id')] = ch
    bt = None
    for ch in row:
        if ch.tag == 'tagged-backtrace': bt = res(ch)
    if bt is None: continue
    bb = bt.find('backtrace')
    if bb is None: bb = bt
    names = []
    for f in bb.iter('frame'):
        f = res(f)
        names.append(f.get('name') or '?')
    if not names: continue
    w = 1
    tot += w
    selfc[names[0]] += w
    for n in set(names): incl[n] += w
print("samples", tot)
print("--- self")
for n, c in selfc.most_common(int(sys.argv[2]) if len(sys.argv) > 2 else 40): print(f"{100*c/tot:5.1f}% {n[:110]}")
print("--- inclusive")
for n, c in incl.most_common(25): print(f"{100*c/tot:5.1f}% {n[:110]}")

# ---- buckets (self time) ----
import re
def bucket(n):
    if 'shared_ptr' in n or 'shared_count' in n or 'shared_weak' in n or 'refcount' in n or 'GCMap::GCMap' in n or 'GCMap::~GCMap' in n or 'Context::Context' in n: return 'Refcounting / struct copies'
    if 'RunInner' in n: return 'VM dispatch'
    if 'hash' in n.lower() and 'Dictionary' not in n or 'Hash' in n: return 'String/value hashing'
    if any(k in n for k in ('findEntry','TryGet','LookupWithOrigin','LookupMember','LookupVariable','RecursiveEqual','Globals::','TryGetValue')): return 'Map lookup'
    if 'ListGet' in n or 'GCList' in n: return 'List access'
    if any(k in n for k in ('xzm','_free','malloc','_tlv','free')): return 'malloc/free'
    if 'GCManager' in n or 'Collect' in n or 'Sweep' in n or 'Mark' in n: return 'GC'
    if any(k in n for k in ('ValueTo','ToValue','ResourceBox')): return 'Binding conversion'
    if n.startswith('rl') or 'gl' in n[:3] or 'DrawTexture' in n: return 'raylib / GL'
    if 'Boolean::operator' in n or 'IsMap' in n or 'Value::' in n: return 'Value helpers (inline wrappers)'
    return 'other'
bc = collections.Counter()
for n, c in selfc.items(): bc[bucket(n)] += c
print("--- buckets")
for n, c in bc.most_common(): print(f"{100*c/tot:5.1f}% {n}")
