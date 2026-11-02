"""PreToolUse/PostToolUse hook: stop the repeat-whole-file-read pattern.

Audited evidence this exists to prevent: in one 9-agent session, single workers read
cast.py 23x, LibraryScene.brs 11x and app.js 10x. Every re-read is re-billed as a
cache-read on every later turn, so a 4k-token file read at turn 10 of 250 costs ~960k.

Policy: 1st read allowed. 2nd allowed with a warning. 3rd+ denied with guidance.
An Edit/Write to a file resets its counter, so re-reading what you just changed is
always allowed. A ranged Read (offset/limit) is never counted. Fails open on any
error - it must never break a session.
"""
import sys, os, json, tempfile, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import savings
except Exception:
    savings = None

STATE_DIR = os.path.join(tempfile.gettempdir(), 'claude-read-guard')
BIG = 25000          # bytes; above this a first read gets a nudge
DENY_AT = 3          # 3rd read of an unchanged file is denied


def allow():
    sys.exit(0)


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        allow()
    d = json.loads(raw)
    tool = d.get('tool_name', '')
    inp = d.get('tool_input', {}) or {}
    fp = inp.get('file_path') or ''
    if not fp:
        allow()

    sid = str(d.get('session_id', 'nosession'))
    os.makedirs(STATE_DIR, exist_ok=True)
    state_path = os.path.join(STATE_DIR, hashlib.md5(sid.encode()).hexdigest() + '.json')
    try:
        state = json.load(open(state_path))
    except Exception:
        state = {}

    key = os.path.normcase(os.path.abspath(fp))

    # An edit invalidates prior reads of that file - re-reading it is legitimate.
    if tool in ('Edit', 'Write', 'NotebookEdit'):
        if key in state:
            del state[key]
            try:
                json.dump(state, open(state_path, 'w'))
            except Exception:
                pass
        allow()

    if tool != 'Read':
        allow()

    # A read of a specific slice is not a whole-file read; don't count it.
    if inp.get('offset') is not None or inp.get('limit') is not None:
        allow()

    try:
        mtime = os.path.getmtime(fp)
    except Exception:
        mtime = 0

    # mtime, not the edit tool, is the real signal a file changed: sed/heredoc edits
    # through Bash, an external editor, or a git checkout all reset the count too.
    prev = state.get(key)
    if isinstance(prev, list) and len(prev) == 2 and prev[1] != mtime:
        prev = None
    n = (prev[0] if isinstance(prev, list) else 0) + 1
    state[key] = [n, mtime]
    try:
        json.dump(state, open(state_path, 'w'))
    except Exception:
        pass

    name = os.path.basename(fp)
    if n >= DENY_AT:
        if savings:
            try:
                model = savings.resolve_model(d.get('transcript_path'), d)
                savings.record('read-guard', 'repeat_read_blocked', model, name,
                               in_tokens=savings.est_tokens_for_file(fp), compounds=True)
            except Exception:
                pass
        # Subagents share the parent's session_id, so this count spans every agent in
        # the session. That is deliberate - N agents each reading the same brief is the
        # waste the digest-at-dispatch rule exists to prevent - but say so plainly, or a
        # worker that has never opened the file finds the message baffling.
        msg = (name + " has already been read " + str(n - 1) + " times in this session "
               "(counting every agent in it) without changing. Re-reading re-bills the whole "
               "file on every later turn. If another agent already read it, get the content "
               "from them or from a digest rather than reading it again. Otherwise: "
               "grep -n 'PATTERN' for a specific symbol, sed -n 'A,Bp' for a known range, or "
               "~/.claude/tools/llm \"your question\" -File '" + fp + "' -Temp 0 for a semantic "
               "question. If you genuinely must re-read, Read it with an offset/limit range.")
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": msg}}))
        sys.exit(0)

    notes = []
    if n == 2:
        notes.append(name + " has now been read twice in this session (any agent) without changing. A third read will be "
                     "blocked; use grep/sed/llm for anything further from this file.")
    # Images are priced by PIXEL AREA, not bytes - a byte-based nudge on a screenshot is
    # simply wrong (it called a 607-token PNG "~7k"). cost-guard.py prices those properly.
    is_img = fp.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'))
    try:
        size = os.path.getsize(fp)
        if n == 1 and size > BIG and not is_img:
            notes.append(name + " is ~" + str(size // 4000) + "k tokens and will be re-billed on every "
                         "later turn of this session. If you only need part of it, prefer grep -n, "
                         "sed -n 'A,Bp', or ~/.claude/tools/llm \"question\" -File '" + fp + "'.")
    except Exception:
        pass

    if notes:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": " ".join(notes)}}))
    sys.exit(0)


try:
    main()
except Exception:
    sys.exit(0)
