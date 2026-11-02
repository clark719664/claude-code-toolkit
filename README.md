# claude-code-toolkit

![License: MIT](https://img.shields.io/badge/license-MIT-blue) ![Platform: Windows](https://img.shields.io/badge/platform-Windows%20%7C%20PowerShell%205.1-informational) ![Python 3](https://img.shields.io/badge/python-3-informational)

Long Claude Code sessions get expensive in a way that isn't obvious at first. Every token in the context is billed again as a cache read on every later turn, so cost grows with turns × context, and context only goes up. One file read early in a long session can end up costing hundreds of times its size. This repo holds the tooling I run on my own machine to keep that under control: two Claude Code hooks that enforce the habits that matter most (no repeat whole-file reads, retire long-running agents), a wrapper that sends mechanical work to a free local Ollama model, a screenshot shrinker, a session audit script, and a small desktop widget that adds up the tokens the local model took on.

Author: Clark Langlois (IN3RT1A)

## What's inside

| File | Type | What it does |
|---|---|---|
| `llm.ps1` (+ `llm`, `llm.cmd`) | PowerShell CLI, with Git Bash and cmd shims | Sends a prompt, plus an optional file, stdin or image, to a local Ollama model and prints the answer. It refuses inputs that won't fit the context window and logs every call to `llm-ledger.csv`. |
| `read-guard.py` | Claude Code hook (PreToolUse on `Read`, PostToolUse on `Edit\|Write\|NotebookEdit`) | Lets a file be read once, warns on the second read, and **denies** the third whole-file read of an unchanged file, with directions to use grep, sed or `llm` instead. |
| `turn-guard.py` | Claude Code hook (PreToolUse on every tool) | Counts tool calls per agent and adds a context message telling long-running workers to wrap up and hand off. It never blocks anything. |
| `shrink.py` | Python CLI (Pillow) | Resizes, crops or grayscales a screenshot before a model reads it, and prints the estimated token cost before and after. |
| `audit.py` | Python CLI | Reads Claude Code session transcripts from `~/.claude/projects` and ranks where the tokens went: context growth per agent, repeat reads, sed-chunking, images, documents read by several agents, and the biggest single reads. |
| `savings-pet.ps1` / `savings-pet-vector.ps1` | WPF desktop widget | Shows the local-model ledger as a running "saved at API rates" total, with a pig that grows as the total rises and goes to sleep when Ollama is offline. |

Also included:

- `bench-model.ps1` scores Ollama models on five tasks that mirror real delegation: verbatim extraction, a yes/no judgement, log triage, code from a spec, and a negative check ("does this mention dragons?" must come back NO). It runs models one at a time and unloads each when it finishes.
- `clean-temp.ps1` frees disk space in `%TEMP%`. By default it only reports what it would delete (items older than 7 days). It deletes only when given `-Go`, and it never touches the hook state folders (`claude`, `claude-read-guard`, `claude-turn-guard`).

## Install

1. Copy the files into `~/.claude/tools/` (on Windows that is `%USERPROFILE%\.claude\tools\`). The `llm` bash shim looks for `llm.ps1` at that path. `llm.cmd` and the widgets work from whatever folder they are in.
2. Install [Ollama](https://ollama.com) and pull the models the wrapper and benchmark use:

   ```sh
   ollama pull qwen3.5:9b                         # default model; also does image transcription
   ollama pull deepseek-r1:8b-0528-qwen3-q4_K_M   # used by -Reason
   ollama pull granite4:tiny-h                    # optional: long inputs, via -Model ... -Ctx 131072
   ```

3. `pip install pillow` for `shrink.py`.
4. Add the hooks to `~/.claude/settings.json`. The snippet is also in [`examples/settings.hooks.json`](examples/settings.hooks.json). Use an absolute path; forward slashes work on Windows as well.

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Read",
           "hooks": [
             { "type": "command", "command": "python \"C:/Users/<you>/.claude/tools/read-guard.py\"", "timeout": 10 }
           ]
         },
         {
           "hooks": [
             { "type": "command", "command": "python \"C:/Users/<you>/.claude/tools/turn-guard.py\"", "timeout": 10 }
           ]
         }
       ],
       "PostToolUse": [
         {
           "matcher": "Edit|Write|NotebookEdit",
           "hooks": [
             { "type": "command", "command": "python \"C:/Users/<you>/.claude/tools/read-guard.py\"", "timeout": 10 }
           ]
         }
       ]
     }
   }
   ```

   Claude Code loads hooks when a session starts, so sessions that are already open won't pick up the change. Opening `/hooks` in a running session reloads the config.

### Using the wrapper

```sh
llm "prompt"                                   # answer to stdout
cat big.log | llm "prompt" -Stdin              # attach stdin (the flag is required)
llm "prompt" -File path -Out out.txt           # attach a file, write the answer to a file
llm "prompt" -System "..." -Temp 0 -Ctx 32768 -MaxTokens 8192
llm "prompt" -Reason                           # deepseek-r1 for harder judgement
llm "prompt" -Think                            # let a reasoning model think first
llm -Image shot.png "Transcribe every piece of text, top to bottom, exactly as written."
llm -Stats                                     # totals from the ledger
```

Thinking is off by default. Both reasoning models will otherwise spend the whole output budget thinking and return an empty answer. The wrapper strips `<think>` blocks and code fences from what it prints. Exit codes: `1` Ollama unreachable, `2` bad input, `3` input too large for `-Ctx`, `4` empty answer.

## How the hooks work

Both hooks read the hook JSON on stdin and answer through `hookSpecificOutput`, either a `permissionDecision: "deny"` or an `additionalContext` note. Each one keeps a small state file under the system temp directory.

**read-guard.py**
- It keeps one counter per session, keyed by `session_id`. Subagents run under their parent's session id, so they share the parent's counter. That is on purpose: when N agents each read the same brief, that is exactly the waste a digest written once at dispatch avoids, and the deny message says so.
- Read 1 is allowed. If the file is over 25,000 bytes (and not an image), the hook also adds a note suggesting grep, sed or `llm`. Read 2 is allowed with a warning. Read 3 or later of a file with the same mtime is denied.
- A Read with `offset`/`limit` set is never counted. A change in mtime resets the count, so edits made through Bash, an external editor or a `git checkout` all count, and the PostToolUse hook clears the counter after `Edit`/`Write`/`NotebookEdit`.
- It also tries to import an optional `savings` module to log blocked reads. That module is not part of this repo, and the hook works without it.

**turn-guard.py**
- It keeps one counter per agent, keyed by `transcript_path`. Subagent transcripts live under a `subagents` path, which is how the hook tells workers apart from the main session.
- For a worker: a nudge at 100 tool calls, then an instruction to finish and write a handoff brief at 120 and every 15 calls after that.
- For the main session: a note at 100 calls and every 60 after that. It is quieter because a main session can't retire itself.

## Rules of use

The habits that make the local model worth using, from my own testing:

- **Send it the mechanical work:** large logs and files, format conversion, boilerplate first drafts, regexes, commit-message drafts, and transcribing screenshots. Keep architecture, security-sensitive code, root-cause calls and final review with Claude.
- **Ask extractive questions, not interpretive ones.** "Is X one of the steps listed in this document?" is reliable. "Does this document describe X?" is not. For a yes/no answer, have the model quote the relevant text first and then conclude.
- **One question and one document per call.** Compound questions over files pasted together fail worst.
- **Treat "nothing found" as unproven.** Local models were most often confidently wrong when the answer was negative. Check with grep.
- **"Where is X defined/called" is a grep question,** and grep is free and exact.
- **Transcription yes, judging appearance no.** Never ask a local vision model whether something is clipped or misaligned. Measure the DOM or look yourself.
- **Review generated code and run it.** It can typecheck and still be wrong.
- **Shrink screenshots before reading them.** Image cost tracks pixel area (roughly `w*h/750` tokens), not file size.
- **Digest at the dispatch boundary.** When several workers need the same brief, the orchestrator digests it once and pastes the digest into each prompt.

## What I measured

These numbers come from my own sessions and machine (16 GB RAM, local models via Ollama). They are not general benchmarks.

- **Why repeat reads matter:** every token in context is billed again as a cache read on every later turn, so a 4k-token read at turn 10 of a 250-turn session costs about 960k cache-read tokens. In one 9-agent session, single workers read the same files 23, 11 and 10 times.
- **Why long agents matter:** one worker ran 535 turns, peaked at 358k context, and used 112M cache-read tokens on its own. I modelled one real 15-agent session with every long agent retired into a fresh one every ~120 turns, and the total fell from 458M tokens to 259M, a saving of 199M tokens (about $44).
- **Why these are hooks and not just instructions:** the same rules written into `CLAUDE.md` and passed on to workers were followed only about 30% of the time.
- **Screenshot shrinking:** a 1920×1080 shot is about 2,764 tokens and about 607 at 900px wide. Against a UI with four planted defects, a truncated label, a cut-off table value and a sidebar item indented 14px too far were all still obvious at 900px. A 5px baseline offset was not, so for alignment, crop at native resolution instead.
- **Vision transcription:** `qwen3.5:9b` transcribed a widget's text exactly right against ground truth in about 24s, which replaces a 15–30k-token image read.
- **Vision judgement:** two different local vision models gave a confident "nothing is clipped" about text that plainly ran off the image, and one invented a log line with a fabricated error code.
- **Question phrasing:** with the same document at temperature 0, "Does this document describe war?" got NO (wrong), and "Is war one of the steps listed in this document?" got YES (right). `bench-model.ps1` carries a version of this test.
- **Generated code:** asked for a ~20-line TypeScript module from an exact spec, `qwen3.5:9b` produced two real bugs. One called a method that doesn't exist (tsc caught it). The other was a guard condition that could never fire, and that one typechecks.
- **Hook safety:** a companion shell-read guard that isn't published here was checked against 60+ cases, 30 of them real command shapes from my projects, and produced zero false denials.

## Known limits

- **The hooks fail open.** Any error, or input they can't parse, exits cleanly and allows the call. They are cost controls, not a security boundary.
- **They only cover what they see.** `read-guard.py` counts the `Read` tool only, so `cat` through a shell gets around it.
- **Windows and PowerShell come first.** `llm.ps1`, the widgets, `bench-model.ps1` and `clean-temp.ps1` target Windows PowerShell 5.1, and the widgets need WPF. The `llm` bash shim needs Git Bash (it uses `cygpath` and calls `powershell.exe`). The Python hooks, `shrink.py` and `audit.py` are plain Python 3.
- **Local models hallucinate,** especially negatives ("there is no X"). Verify anything load-bearing.
- **The widget's dollar figure is an estimate.** It prices ledger tokens at constants set at the top of each widget script (`$inRate`, `$outRate`, per million tokens). Edit them to match the model you would otherwise have paid for. The `llm -Stats` figure is local input plus output tokens, a stand-in for the Claude tokens avoided.
- **The sprite widget has no art in this repo.** `savings-pet.ps1` loads sprite frames from `pig/frames3/` (e.g. `base_idle_1.png`), and I haven't published that art. Without it there is no pig; the rank, total and progress bar still show. `savings-pet-vector.ps1` draws its pig with WPF shapes and needs no art. Its "switch back to sprite" menu item expects a `Qwen Savings Pet.vbs` launcher, which is also not included.
- **`audit.py` uses defaults that suit me.** It looks at the most recently modified project folder under `~/.claude/projects` and, unless you pass a session id, picks the largest session file there.
- **RAM:** on a 16 GB machine, keep only one local model loaded at a time (`ollama ps`, `ollama stop <name>`).

## License

MIT. See [LICENSE](LICENSE). Copyright 2026 Clark Langlois.
