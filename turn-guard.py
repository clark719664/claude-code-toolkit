"""PreToolUse hook: make the retire-at-~120-turns rule always-delivered.

Measured on a real 15-agent session: cost is turns x context and context only grows,
so a long agent gets quadratically expensive (one worker: 535 turns, 358k peak
context, 112M cache-read tokens alone). Retiring long agents into fresh ones every
~120 turns modelled a 199M-token saving on that session. The same rule written in
CLAUDE.md landed about 30% of the time; this fires at the moment it matters.

Keyed by transcript_path, which is per-agent (subagents get their own transcript),
so each worker and the orchestrator are counted separately. Never denies - it only
injects context - so it cannot trap work. Fails open on any error.
"""
import sys, os, json, tempfile, hashlib

STATE_DIR = os.path.join(tempfile.gettempdir(), 'claude-turn-guard')
SOFT = 100      # first nudge
HARD = 120      # retire point
REPEAT_SUB = 15 # subagent: remind every N calls past HARD
REPEAT_MAIN = 60 # main/interactive session: much quieter, it cannot retire itself


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    d = json.loads(raw)
    key = str(d.get('transcript_path') or d.get('session_id') or '')
    if not key:
        return
    is_sub = 'subagents' in key.replace('\\', '/')
    os.makedirs(STATE_DIR, exist_ok=True)
    sp = os.path.join(STATE_DIR, hashlib.md5(key.encode()).hexdigest() + '.txt')
    try:
        n = int(open(sp).read().strip() or 0)
    except Exception:
        n = 0
    n += 1
    try:
        open(sp, 'w').write(str(n))
    except Exception:
        pass

    msg = None
    if is_sub:
        if n == SOFT:
            msg = ("TURN BUDGET: this worker is at " + str(n) + " tool calls. Context re-bills on every call and only "
                   "grows. Plan to finish the current task and stop by ~" + str(HARD) + ". If work remains, write a "
                   "short handoff brief (done / left / key file:line refs) so a FRESH worker can continue.")
        elif n >= HARD and (n - HARD) % REPEAT_SUB == 0:
            msg = ("TURN BUDGET EXCEEDED: this worker is at " + str(n) + " tool calls. Every further call re-bills the "
                   "whole context. Finish now: save state, write the handoff brief, and return. Do not start new "
                   "sub-tasks; the orchestrator will dispatch a fresh worker.")
    else:
        if n == SOFT or (n > SOFT and (n - SOFT) % REPEAT_MAIN == 0):
            msg = ("CONTEXT COST: this session is at " + str(n) + " tool calls and its context re-bills on every one. "
                   "Keep it lean: read worker reports as digests not files, never resume a worker past ~120 turns "
                   "(dispatch a fresh one with a handoff brief), shrink screenshots before reading, and consider "
                   "/compact at a natural checkpoint.")
    if msg:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": msg}}))


try:
    main()
except Exception:
    pass
sys.exit(0)
