"""Find where a Claude Code session is wasting tokens. Usage:
     python ~/.claude/tools/audit.py              # busiest session in this project today
     python ~/.claude/tools/audit.py <session-id> # a specific session
     python ~/.claude/tools/audit.py --since 2026-09-14T21:00
Reports the levers in cost order: context growth, repeat reads, images, duplicated docs."""
import sys, io, json, os, glob, collections, datetime
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

PROJECTS = os.path.expanduser(r'~/.claude/projects')
args = [a for a in sys.argv[1:]]
since = '1970'
if '--since' in args:
    i = args.index('--since'); since = args[i+1]; del args[i:i+2]
sid = args[0] if args else None

proj = max(glob.glob(os.path.join(PROJECTS, '*')), key=os.path.getmtime)
if not sid:
    cands = [f for f in glob.glob(os.path.join(proj, '*.jsonl'))]
    if not cands: sys.exit('no sessions found')
    sid = os.path.basename(max(cands, key=os.path.getsize))[:-6]
main = os.path.join(proj, sid + '.jsonl')
if not os.path.exists(main): sys.exit(f'no such session: {main}')
files = [main] + sorted(glob.glob(os.path.join(proj, sid, 'subagents', '*.jsonl')))

agents = {}; dupdoc = collections.defaultdict(set); grand_img = 0
for f in files:
    name = 'CONTROLLER' if f == main else os.path.basename(f)[6:12]
    turns = 0; cache = 0; llm = 0; reads = collections.Counter()
    big = []; imgs = []; uses = {}; slices = collections.Counter()
    for line in open(f, encoding='utf-8', errors='ignore'):
        try: d = json.loads(line)
        except: continue
        if d.get('timestamp', '') < since: continue
        m = d.get('message', {}); c = m.get('content')
        if d.get('type') == 'assistant':
            turns += 1; cache += m.get('usage', {}).get('cache_read_input_tokens', 0)
        if not isinstance(c, list): continue
        for b in c:
            if b.get('type') == 'tool_use':
                inp = b.get('input', {}); uses[b['id']] = (b['name'], inp)
                blob = json.dumps(inp)
                if 'tools/llm' in blob or 'rep.sh' in blob or 'prereview.sh' in blob: llm += 1
                cmd = inp.get('command', '')
                if 'sed -n' in cmd:
                    for tok in cmd.split():
                        if tok.endswith(('.md', '.py', '.js', '.brs', '.txt', '.json')):
                            slices[tok.strip('"\'')] += 1
            if b.get('type') == 'tool_result':
                t = b.get('content'); n_img = 0
                if isinstance(t, list):
                    for x in t:
                        if isinstance(x, dict) and x.get('type') == 'image':
                            n_img += 1
                    t = ''.join(x.get('text', '') for x in t if isinstance(x, dict))
                t = t or ''
                u = uses.get(b.get('tool_use_id'))
                if not u: continue
                tname, inp = u
                if n_img: imgs.append((turns, n_img))
                fp = inp.get('file_path', '')
                if tname == 'Read' and fp:
                    reads[fp] += 1
                    if any(k in fp.lower() for k in ('brief', 'report', 'progress', 'plan', 'review', 'spec')):
                        dupdoc[os.path.basename(fp)].add(name)
                if len(t) > 2500:
                    desc = fp or inp.get('command', '') or inp.get('pattern', '')
                    big.append((len(t)//4, tname, str(desc).replace('\n', ' ')[:70]))
    if turns:
        img_cost = sum(1150 * n * max(0, turns - at) for at, n in imgs)
        grand_img += img_cost
        agents[name] = dict(turns=turns, cache=cache, llm=llm, reads=reads,
                            big=big, imgs=sum(n for _, n in imgs), img_cost=img_cost,
                            slices=slices)

print(f'session {sid}   {len(agents)} agents' + (f'   since {since}' if since != '1970' else ''))
total = sum(a['cache'] for a in agents.values())
print(f'\n=== 1. CONTEXT COST  (total {total:,} cache-read tokens; re-billed every turn) ===')
for n, a in sorted(agents.items(), key=lambda z: -z[1]['cache'])[:10]:
    print(f"  {n:12} {a['turns']:4} turns  {a['cache']:13,}  avg ctx/turn {a['cache']//a['turns']:>8,}  llm calls {a['llm']}")

print('\n=== 2. REPEAT READS  (each costs face value x turns remaining) ===')
any_rep = False
for n, a in agents.items():
    rep = [(p, c) for p, c in a['reads'].items() if c >= 2]
    if rep:
        any_rep = True
        print(f'  {n}: ' + ', '.join(f'{os.path.basename(p)} x{c}' for p, c in sorted(rep, key=lambda z: -z[1])[:6]))
if not any_rep: print('  none - good')

print('\n=== 3. SED-CHUNKING  (consecutive slices = reading the whole file) ===')
any_sl = False
for n, a in agents.items():
    sl = [(p, c) for p, c in a['slices'].items() if c >= 3]
    if sl:
        any_sl = True
        print(f'  {n}: ' + ', '.join(f'{os.path.basename(p)} {c} slices' for p, c in sorted(sl, key=lambda z: -z[1])[:5]))
if not any_sl: print('  none - good')

print(f'\n=== 4. IMAGES  (~{grand_img:,} cache-read tokens caused) ===')
for n, a in sorted(agents.items(), key=lambda z: -z[1]['img_cost']):
    if a['imgs']:
        print(f"  {n:12} {a['imgs']:3} images -> ~{a['img_cost']:11,} tok   (shrink.py, and verify LATE)")
if not grand_img: print('  none')

print('\n=== 5. SAME DOC READ BY MULTIPLE AGENTS  (digest once at dispatch instead) ===')
shown = False
for doc, ws in sorted(dupdoc.items(), key=lambda z: -len(z[1])):
    if len(ws) > 1:
        shown = True; print(f'  {doc[:55]:57} read by {len(ws)}: {",".join(sorted(ws))}')
if not shown: print('  none - good')

print('\n=== 6. BIGGEST SINGLE DIRECT READS ===')
allbig = sorted(((tok, n, tname, d) for n, a in agents.items() for tok, tname, d in a['big']), reverse=True)[:10]
for tok, n, tname, d in allbig:
    print(f'  {tok:6,} tok  {n:12} {tname:6} {d}')
