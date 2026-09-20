# Run log - Bank Creditor demo

A record of the steps actually run on Mahesh's Mac, in order, with real results.
Companion to `HOW_TO_RUN.md`, which is the plan. This file is the truth.

Machine: MacBook Pro, macOS on **Intel x86_64**. Shell is `bash`, not zsh.
Path chosen: **A** (laptop, no Diagrid account), then **B** (Catalyst Cloud).
Started 2026-09-19.

---

## Step 1. Check the tools - PASS with one gap

```bash
docker --version
docker compose version
docker info --format '{{.ServerVersion}}'
uv --version
lsof -nP -iTCP:5432 -iTCP:8000 -iTCP:9000 -sTCP:LISTEN
```

| Check | Result |
|---|---|
| Docker | 23.0.5, build bc4487a |
| Docker Compose | v2.17.3 |
| Docker daemon | 23.0.5, running |
| uv | **not installed** |
| Ports 5432 / 8000 / 9000 | all free, no output |

Docker 23.0.5 is old but fine. The compose file needs `host-gateway` in
`extra_hosts`, which has worked since Docker 20.10.

---

## Step 2, attempt 1. `brew install uv` - ABANDONED, do not repeat

```bash
if command -v brew >/dev/null 2>&1; then brew install uv; else curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$PATH"; fi
```

Homebrew stopped at the confirmation prompt and then aborted. Nothing was installed.

What it wanted to do first:

```
Would install 1 formula: uv 0.12.17
Would install 10 dependencies: pkgconf libssh2 llhttp libgit2 cmake ninja
                               mpdecimal python@3.14 llvm@22 rust
```

Why that is wrong here:

```
Warning: You are using macOS on Intel x86_64.
Homebrew no longer builds bottles for this configuration.
Existing bottles may still work, but updated formulae may build from source.
```

A bottle is a prebuilt binary. With no bottle, Homebrew compiles from source.
`llvm@22` and `rust` are the two largest compiles in the whole catalog. On this
machine that is hours, to install one tool that ships a ready-made binary.

**Standing rule for this project: on this Mac, prefer the vendor's own install
script over Homebrew for anything Homebrew would build from source.** This
applies again at the Dapr command-line tool in Part 3.

Second Homebrew note for later: `brew` now requires tap trust, and
`hashicorp/tap` is already untrusted on this machine. `brew install dapr/tap/dapr-cli`
would hit the same wall.

## Step 2, attempt 2. `brew install uv`, deliberately - ABANDONED mid-build

Mahesh chose Homebrew first, for familiarity. It got as far as compiling
`llvm@22` with clang, clang-tools-extra and MLIR from source:

```
==> cmake -G Ninja .. -DLLVM_ENABLE_PROJECTS=clang;clang-tools-extra;mlir;
==> cmake --build .
```

That is only the first of three chained source builds: llvm@22, then rust, then
uv. Stopped with Ctrl+C. Nothing already installed was harmed. Disk was never
the issue, 1.4 TB free.

## Step 2, attempt 3. Direct installer - PASS

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
uv --version
```

```
downloading uv 0.12.17 x86_64-apple-darwin
installing to /Users/maheshrajannan/.local/bin
uv 0.12.17 (635500036 2026-09-18 x86_64-apple-darwin)
```

Seconds, prebuilt Intel binary. Upgrades later with `uv self update`.

**PATH note, matters for every later step.** The `export PATH` above applies to
that one tab only. In any other Terminal tab, run this first, or open a fresh
tab so the shell reads `~/.bash_profile`:

```bash
source $HOME/.local/bin/env
```

If a later step says `uv: command not found`, this is why.

## Step 3. Start Postgres, the MCP server and the web page - PASS

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml up -d --build
docker compose -f local/compose.yaml ps
curl -s http://localhost:9000/healthz
open http://localhost:9000
```

```
{"status":"ok"}
```

Both containers came up and the web page opened in the browser. Docker 23.0.5
and Compose v2.17.3 handled the compose file without complaint, including
`host.docker.internal:host-gateway`, which is how the MCP container will call
back to the agent on the Mac at port 8000.

## Step 4. Start the plain agent - PASS

New Terminal tab. This is the "before" picture: LangGraph with nothing durable
underneath it.

```bash
cd ~/git/agent-durability-demo/services/agent-plain
uv sync
MCP_URL=http://localhost:9000/mcp/ uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

```
Resolved 61 packages in 5ms
Checked 59 packages in 24ms
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

`uv sync` finished in 29 ms because the packages were already in uv's global
cache. No macOS firewall prompt appeared.

Web page state before pressing anything, confirmed by screenshot:

| Panel | Value |
|---|---|
| Accounts | 10, each $100.00, total $1,000.00 of $2,000.00 |
| Transactions processed | 0 |
| Agents | idle 10, alive 0 |
| MCP server calls | CONNECTED, `mcp://postgres.bank...` session opened |
| Kubernetes cluster | no live pods detected (expected, this is a laptop) |
| Chaos buttons | Pod failure and AZ failure greyed out (expected) |

**Browser tip:** the window cuts off the **Reset** button on the right. Zoom out
with Cmd and minus until it is visible. Reset is needed from Step 6 onward.

## Step 5. The "before" demo: plain agent loses its work - PASS

All in the browser, with the plain agent still running.

1. Press **Start run**. Watch TRANSACTIONS PROCESSED climb. No pacing in this
   variant, so the full 1,000 takes about a minute.
2. At 20 to 30 seconds, press Ctrl+C in the agent tab. The counter stops.
3. Restart the agent with the same command. **Do not press Start run again.**
4. The counter stays frozen. That is the whole point.

Watch TRANSACTIONS PROCESSED, not the agent tiles. The tiles infer "alive" from
the run state, not from the process, so they can lie after a kill.

**Result: PASS. Frozen at 173 of 1,000.**

Killed at about 25 seconds into run #2. Ctrl+C produced one harmless line,
`RuntimeWarning: coroutine 'connect_tcp...' was never awaited`, which is just an
HTTP request that was in flight when the signal landed.

After restarting the agent, the counter never moved again. Balances stayed at
$116 to $119 out of $200.

**The screen lied, exactly as warned.** With no agent process doing any work the
page still showed `AGENTS ALIVE 10 / 10, 100% online`, because it infers "alive"
from the run state. Use TRANSACTIONS PROCESSED, or the database.

## Step 6. Prove the "before" number from the database - PASS

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml exec postgres psql -U bankadmin -d bankdemo -c "SELECT execution_run_id, COUNT(*), SUM(amount) FROM transactions GROUP BY 1 ORDER BY 1 DESC LIMIT 3;"
```

```
 execution_run_id | count |  sum
------------------+-------+--------
                2 |   173 | 173.00
```

**173 of 1,000. This is the "before" half of the demo.** Run the same query
again after Part 3 and the durable run should read 1000 and 1000.00.

## Step 7. Clear the deck for the durable agent - DONE

1. Press **Stop run** in the browser.
2. Press Ctrl+C in the plain agent tab, to free port 8000.

No Reset needed. Start run resets the balances by itself.

**Result: done.** Port 8000 free.

## Step 8. Install Dapr - PASS, already present

```bash
curl -fsSL https://raw.githubusercontent.com/dapr/cli/master/install/install.sh | /bin/bash
dapr --version
dapr init --runtime-version 1.18.2
docker ps --format '{{.Names}}' | grep dapr_
```

**Homebrew is the wrong path again, and this was checked before running it.**
`dapr/homebrew-tap/dapr-cli.rb` does `url ".../cli/archive/v1.18.0.tar.gz"` with
`depends_on "go" => :build`, and its only bottle is `arm64_sequoia`. On Intel
that is a source build plus a third-party tap-trust prompt. The install script
downloads a prebuilt `darwin_amd64` binary instead.

Expect a `sudo` password prompt to place the binary in `/usr/local/bin`.

**Result: PASS, and `dapr init` was not needed.**

```
Your system is darwin_amd64
Dapr CLI is detected: CLI version 1.18.0, Runtime version 1.18.2
Downloading .../v1.18.2/dapr_darwin_amd64.tar.gz
dapr installed into /usr/local/bin successfully.
CLI version: 1.18.2   Runtime version: 1.18.2
```

Dapr was already on this Mac from earlier work. The script upgraded the CLI from
1.18.0 to 1.18.2 and left the runtime alone, which was already 1.18.2. All four
containers were already running:

```
dapr_zipkin     Up 2 hours (healthy)
dapr_scheduler  Up 2 hours
dapr_placement  Up 2 hours
dapr_redis      Up 2 hours
```

Check before you initialise. `dapr init` would have been a wasted download.

## Step 9. Apply the MCP direct patch - PASS

The durable agent has the Catalyst tool-call address hard-coded. The patch adds
one optional setting, `MCP_DIRECT_URL`, so the agent can call the MCP server
directly on the laptop. With the setting unset, the code behaves as before.

```bash
cd ~/git/agent-durability-demo
git apply local/mcp-direct.patch
git diff --stat services/agent-langgraph/
```

Expect exactly: `1 file changed, 3 insertions(+), 2 deletions(-)` in
`services/agent-langgraph/agent_worker/mcp_client.py`.

**Result: PASS. Applied clean, exactly that diffstat.**

Undo it when done with Part 3, and do not commit it:

```bash
git checkout -- services/agent-langgraph/agent_worker/mcp_client.py
```

## Step 10. Run the durable agent - PASS

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
uv sync
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8000 -H 3500 -G 50001 -M 9091 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

Wait for these four lines before touching the browser:

```
Registering workflow 'dapr.langgraph.Banker.workflow' with runtime
Registered node: agent
Registered node: tools
runner started (stub=True)
```

`STUB_LLM=true` means a fixed decision function stands in for the LLM (large
language model), so no model key is needed. Do not set it to false. All three
agent variants raise an error in that mode.

**Result: PASS. Up in 18 seconds.**

```
INFO:diagrid.agent.core.workflow.runner:Dapr Workflow runtime started
INFO:main:runner started (stub=True)
INFO:     Uvicorn running on http://0.0.0.0:8000
INFO[0018] application discovered on port 8000
INFO[0018] dapr initialized. Status: Running. Init Elapsed 18364ms
INFO[0018] Connected to placement localhost:50005
INFO[0018] Scheduler stream connected for [JOB_TARGET_TYPE_JOB]
```

Two 404s appear and are harmless: `GET /dapr/config` and `GET /dapr/subscribe`.
Dapr probes every app for those endpoints. This app defines neither.

The line that matters is `runner started (stub=True)`. The placement and
scheduler connections are the ledger being wired up. That is the whole
difference from Part 2.

## Step 11. Kill the durable agent and watch it recover - PASS

1. Press **Start run**. Paced at one credit per account every 0.3 s, so the full
   1,000 takes about two minutes.
2. Mid-run, press Ctrl+C in the agent tab. Note the frozen number.
3. Wait 10 seconds so the freeze is visible on screen.
4. Start the agent again with the same `dapr run` command.
   **Do not press Start run.** Start means new run and wipes every balance.
5. Within 10 to 20 seconds the balances climb again, from where they stopped.

**Result: PASS. Run #3 froze at 201, resumed on its own, passed 507.**

| Moment | Transactions | Note |
|---|---|---|
| Ctrl+C at 00:58 | **201** of 1,000 | balances $119 to $121 |
| Restart, no button pressed | climbing again | ~18 s of Dapr startup first |
| 02:13 | **507** of 1,000 | balances $151 to $153 |

The kill was clean: `Worker shutdown completed`, `Dapr Workflow runtime stopped`,
`The App process exited with error code: 143`. Code 143 is SIGTERM, which is what
Ctrl+C sends. It is not an error.

**This is the demo.** Nobody pressed Start. The ten workflows were mid-step when
the process died. The new process read the ledger and each account carried on
from its own last committed dollar.

Side by side with Part 2, on the same laptop, same 1,000 transactions:

| | Plain agent | Durable agent |
|---|---|---|
| Killed at | 173 | 201 |
| After restart | 173, forever | resumed, then 507 and climbing |
| Button pressed to recover | none would help | none needed |

## Step 12. Let it finish, then prove the invariant - PASS

Wait for TRANSACTIONS PROCESSED to reach 1,000 and ACCOUNTS AT TARGET to read
10 / 10. About another minute at 0.3 s pacing. Then:

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml exec postgres psql -U bankadmin -d bankdemo -c "SELECT execution_run_id, COUNT(*), SUM(amount) FROM transactions GROUP BY 1 ORDER BY 1 DESC LIMIT 3;"
```

Expect run 3 at `1000 | 1000.00` next to run 2 at `173 | 173.00`. One table, both
halves of the argument.

**Result: PASS. Path A is proven end to end.**

```
 execution_run_id | count |   sum
------------------+-------+---------
                3 |  1000 | 1000.00     <- durable, killed at 201, recovered
                2 |   173 |  173.00     <- plain, killed at 173, stayed there
```

Exactly 1,000 transactions and exactly $1,000 credited, on a run whose process
was killed halfway through. Not 999, not 1,001. The primary key on
`(execution_run_id, tx_id)` plus `INSERT ... ON CONFLICT DO NOTHING` is what
makes a replayed step harmless.

**Show this query, not the dashboard.** The dashboard claimed `AGENTS ALIVE 10/10`
while nothing was running. The table cannot lie.

## Step 13. Chaos buttons - PASS

Needs an active run, so press **Reset**, then **Start run** first.

| Button | Works here? | What it does |
|---|---|---|
| MCP Latency: 10s | yes | 3 extra seconds per tool call, for 10 seconds |
| MCP tool call failure | yes | next tool call fails, the step retries |
| Pod failure | no, greyed out | deletes real Kubernetes pods |
| AZ failure | no, greyed out | needs a cluster spread across zones |

Watch TRANSACTIONS LOST stay at 0 and the run still finish at 1,000.

**Result: run #5 completed. 10 / 10 accounts at $200.00, $2,000.00 of $2,000.00,
TRANSACTIONS LOST 0, MCP server calls 1000 queries.**

**Dashboard bug worth knowing before you present.** At the end of run #5 the
panels disagreed with each other:

| Panel | Reading |
|---|---|
| TRANSACTIONS PROCESSED | **999** |
| ACCOUNTS AT TARGET | 10 / 10, 100.0% of run |
| ACCOUNTS total | $2,000.00 / $2,000.00 |
| MCP SERVER CALLS | 1000 queries |
| Call log, last line | `credit_next run=5 cust=9 +$1 tx=tx-c9-100` then `applied cust=9 balance=$200.0` |

Ten accounts at exactly $200 each means 1,000 credits landed. The counter is one
behind. It is a display race at the finish, not a lost transaction. Same lesson
as Step 6: **the counter is decoration, the table is the evidence.**

If someone in the audience reads 999 off the screen, answer with the query, not
with the dashboard.

**Both chaos buttons were pressed during run #5. PASS.**

```
 execution_run_id | count |   sum
------------------+-------+---------
                5 |  1000 | 1000.00   <- durable + 3s latency + a forced tool failure
                3 |  1000 | 1000.00   <- durable, process killed at 201
                2 |   173 |  173.00   <- plain, process killed at 173
```

Three rows, one query, the whole argument. That table is the slide.

The 999 on the dashboard was indeed a display bug. The database says 1000.

---

# Path A is complete

Everything in Parts 0, 1, 2, 3 and 5 of `HOW_TO_RUN.md` has now been run on this
Mac and matches what the guide predicted. Total elapsed about 2 hours, roughly
half of it spent on the two Homebrew-on-Intel detours in Steps 2 and 8.

## Close-out, 2026-09-19

Stopped here for the night. Part 4 deferred.

```bash
cd ~/git/agent-durability-demo
git checkout -- services/agent-langgraph/agent_worker/mcp_client.py
docker compose -f local/compose.yaml down
```

Ctrl+C the `dapr run` tab first.

**`down` without `-v` on purpose.** The volume keeps runs 2, 3 and 5, so the
proof query still works next time. `down -v` would delete them.

Leave the four `dapr_` containers alone. They predate this exercise.

To pick up again:

```bash
docker compose -f local/compose.yaml up -d
git apply local/mcp-direct.patch
cd services/agent-langgraph
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8000 -H 3500 -G 50001 -M 9091 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

## Files added or changed today

| File | What it is | In git? |
|---|---|---|
| `RUN_LOG.md` | this file | new, uncommitted |
| `what-is-uv.md` | short note on uv with a Mermaid diagram | new, uncommitted |
| `HOW_TO_RUN.md` | Part 3.1 corrected, Homebrew to the Dapr install script | modified, uncommitted |
| `services/agent-langgraph/agent_worker/mcp_client.py` | patched, then reverted | unchanged |
| `Claude outputs/` | not created by Claude. Holds a **stale** copy of `bank-creditor-app-flow-80-20.md` from 1:23 PM that still references a deleted SVG, plus a chat preview PNG. | untracked |

## What is left

| Part | What it adds | Time | Tested by Claude? |
|---|---|---|---|
| 4. Catalyst Cloud | the Catalyst console: app graph, agent page, workflow history | 45-60 min | no |
| 6. Kubernetes self-hosted | the Pod failure and AZ failure buttons | half a day | no |

Part 4 needs a free account at catalyst.diagrid.io and the `diagrid` CLI.

---

## Path A summary

Numbers match the step headings above.

| Step | Guide section | Result |
|---|---|---|
| 1. Check the tools | Part 0 | PASS, uv missing |
| 2. Install uv | Part 0 | PASS on the third attempt, direct installer |
| 3. Postgres, MCP server, web page | Part 1 | PASS |
| 4. Start the plain agent | Part 2 | PASS |
| 5. Plain agent loses its work | Part 2 | PASS, frozen at 173 of 1,000 |
| 6. Prove the "before" number in SQL | Part 2 | PASS, 173 / 173.00 |
| 7. Clear the deck | - | done |
| 8. Install Dapr | Part 3.1 | PASS, already present, CLI upgraded |
| 9. Apply the MCP direct patch | Part 3.2 | PASS |
| 10. Run the durable agent | Part 3.3 | PASS, up in 18 s |
| 11. Kill it and watch it recover | Part 3.4 | PASS, 201 to 507 unattended |
| 12. Finish, prove the invariant | Part 3.5 | PASS, 1000 / 1000.00 |
| 13. Chaos buttons | Part 5 | PASS, 1000 / 1000.00 under chaos |

Still to run: Modes 1 to 4 in `run-modes.md`.

---

# Mode 1. Two copies, failover with no restart

Started 2026-09-20. See `run-modes.md` for how the modes fit together.

**The claim being tested is different from last night's.** Last night proved
"the work survives a restart". Mode 1 proves "the work survives without one".
A second copy of the agent picks up the dead copy's accounts while the run keeps
going. That is the laptop equivalent of a pod dying and a healthy pod taking over.

`HOW_TO_RUN.md` section 3.6.

Starting state: the `MCP_DIRECT_URL` patch is committed (`401c1a5`), so there is
nothing to apply this time.

## M1 Step 1. Bring the stack back up - PASS

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml up -d
docker compose -f local/compose.yaml ps
curl -s http://localhost:9000/healthz
docker ps --format '{{.Names}}' | grep dapr_
open http://localhost:9000
```

No rebuild needed. No `-v` was used last night, so the volume still holds runs
2, 3 and 5.

```
{"status":"ok"}
dapr_zipkin
dapr_scheduler
dapr_placement
dapr_redis
```

Containers came straight back. Nothing rebuilt, nothing re-downloaded.

## M1 Step 2. Start copy A on port 8000 - PASS

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8000 -H 3500 -G 50001 -M 9091 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

Identical to Step 10. Wait for `runner started (stub=True)`.

**Copy A is the one the buttons talk to.** `local/compose.yaml` sets
`AGENT_HTTP_BASE: http://host.docker.internal:8000`, so Start run and Stop run
always reach port 8000. Copy A must stay alive for the whole of Mode 1.

**Result: PASS. Up in 4.4 seconds this time, against 18 the first night, because
the packages and images were already warm.**

```
INFO:main:runner started (stub=True)
INFO[0004] Connected to placement service: localhost:50005
INFO[0004] Reporting initial host to placement service with initial types
          [dapr.internal.default.bank-agent-creditor.workflow
           dapr.internal.default.bank-agent-creditor.retentioner
           dapr.internal.default.bank-agent-creditor.activity]
INFO[0004] Dissemination complete for version 1
          ... unlocking disseminator default/bank-agent-creditor
```

**Those last two lines are the mechanism Mode 1 is about.** The placement
service keeps a table of which host owns which workflow. Copy A has just
reported in and the table is at version 1, with one host in it.

Watch that same tab when copy B joins. The table goes to version 2 and the ten
workflows get split across both hosts. When copy B dies it goes to version 3 and
B's share moves back to A. That is failover, and it is a table update, not a
restart.

Also of note: `Component loaded: statestore (state.redis/v1)` and
`Using 'statestore' as actor state store`. That Redis container is the ledger in
this mode.

## M1 Step 3. Start copy B on port 8001 - PASS

A **new** Terminal tab. Copy A keeps running.

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8001 -H 3501 -G 50002 -M 9092 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8001
```

Four numbers change: 8001, 3501, 50002, 9092.

**The app id does NOT change.** Both copies run as `bank-agent-creditor`. That is
the whole trick. Same id means two replicas of one logical app, so placement
shares the workflows between them. A different id would mean two unrelated apps
and no failover at all.

**Result: PASS. Copy A's tab announced the table rewrite the moment B joined.**

```
INFO[0463] Dissemination complete for version 2
          (changed types [...activity ...retentioner ...workflow])
          unlocking disseminator default/bank-agent-creditor
```

Version 1 was one host. Version 2 is two. Nothing was restarted and nothing was
configured. Copy B simply reported in under the same app id and placement
redistributed ownership.

## M1 Step 4. Start a run and confirm BOTH copies are working - PASS

In the browser: **Reset**, then **Start run**.

Then watch both agent tabs. Both should print lines like:

```
INFO:httpx:HTTP Request: POST http://localhost:9000/mcp/ "HTTP/1.1 200 OK"
```

**Why copy B does any work at all is the non-obvious part.** The MCP server only
ever calls port 8000, because `local/compose.yaml` sets
`AGENT_HTTP_BASE: http://host.docker.internal:8000`. So copy A receives all ten
schedule-one requests. But scheduling a workflow is not the same as running it.
Copy A hands each one to the Dapr workflow engine, and placement decides which
host owns it. Roughly half land on copy B.

If only copy A prints tool calls, the split did not happen. Stop and say so.

**Result: PASS. Run #9. The ten workflows split across both copies.**

Two Terminal windows, colour coded. Blue is copy A on 8000, green is copy B on
8001. Both printing `POST localhost:9000/mcp/` and `[ACTIVITY] Executing node`.

Ownership at 16:08:06, read off the workflow instance ids
(`agent-00X-r1789938433`):

| Copy | Accounts it was running |
|---|---|
| A (blue, port 8000) | agent-001, agent-006, agent-009, agent-010 |
| B (green, port 8001) | agent-002, agent-004, agent-007 |

Nothing assigned those. Placement did, from the version 2 table.

## M1 Step 5. Kill copy B mid-run - PASS

Ctrl+C in the green tab at 16:08:27.

```
INFO: Stopping gRPC worker...
INFO: No longer listening for work items
INFO: Worker shutdown completed
INFO:diagrid.agent.langgraph.runner:Dapr Workflow runtime stopped
❌  The App process exited with error code: 143
```

**40 seconds later, copy A was running copy B's accounts.** Blue tab at
16:09:07:

```
16:09:07.872  agent-002-r1789938433: Orchestrator yielded with 1 task(s)
16:09:07.941  agent-001-r1789938433: Orchestrator yielded with 1 task(s)
16:09:07.968  agent-009-r1789938433: Orchestrator yielded with 1 task(s)
16:09:08.015  agent-010-r1789938433: Orchestrator yielded with 1 task(s)
16:09:08.067  agent-002-r1789938433: Orchestrator yielded with 1 task(s)
```

`agent-002` is the proof. It was copy B's before the kill and it is copy A's
after, and **the run never stopped to make that happen**. No restart, no button,
no Start run.

The step counters in that slice read `Step 197` and `Step 201`. One dollar costs
about two workflow steps, so 100 dollars is about 201 steps. Those accounts were
finishing as the handover happened.

**This is the claim Mode 1 exists to make.** Last night: the work survives a
restart. Today: the work survives without one. In Kubernetes terms, last night
was a pod restarting, today is a pod dying and its replicas absorbing the load.

## M1 Step 6. Let it finish and prove the invariant - PASS

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml exec postgres psql -U bankadmin -d bankdemo -c "SELECT execution_run_id, COUNT(*), SUM(amount) FROM transactions GROUP BY 1 ORDER BY 1 DESC LIMIT 4;"
```

Run 9 should read `1000 | 1000.00`, with one agent copy dead for the second half
of it.

**Result: PASS. Run 9 finished at 1000 / 1000.00 with one of the two agent
copies dead for the back half of it.**

```
 execution_run_id | count |   sum
------------------+-------+---------
                9 |  1000 | 1000.00   <- two copies, copy B killed mid-run, NO restart
                5 |  1000 | 1000.00   <- one copy, 3s latency and a forced tool failure
                3 |  1000 | 1000.00   <- one copy, process killed at 201 and restarted
                2 |   173 |  173.00   <- plain agent, killed at 173, never recovered
```

**Four rows, one query. That is the entire demo.** Row 2 is the problem. Rows 3,
5 and 9 are three different failures the same design absorbs, and every one of
them lands on exactly 1,000 and exactly $1,000.

---

# Mode 1 is complete

| Failure | Mode | Result |
|---|---|---|
| Process dies, you restart it | run 3 | resumes from the ledger, 1000 |
| Slow tool calls and a hard tool failure | run 5 | retries the step, 1000 |
| A replica dies, nobody restarts anything | run 9 | the survivor absorbs its accounts, 1000 |

Elapsed: about 35 minutes including writing `run-modes.md`.

## Log capture, added during Mode 1

`local/run-agent.sh A|B` starts a copy with the right ports, the shared app id,
`PYTHONUNBUFFERED=1` and `tee` to a timestamped file under `logs/`.

`PYTHONUNBUFFERED=1` is not optional. Python buffers when stdout is a pipe
rather than a terminal, so without it the uvicorn and workflow lines arrive in
chunks and the last ones are lost on Ctrl+C. Dapr's own lines are unaffected.

`logs/` is gitignored. Curated excerpts live here instead.

## Final dashboard state of run 9, and two things to know before presenting

| Panel | Reading |
|---|---|
| TRANSACTIONS PROCESSED | **1,000** |
| ACCOUNTS AT TARGET | 10 / 10, 100.0% |
| Accounts total | $2,000.00 / $2,000.00 |
| TRANSACTIONS LOST | 0 |
| AGENTS KILLED | **0** |
| MCP server calls | 1000 queries |

**The counter read 1,000 this time.** Run 5 showed 999 at the same point. So that
was a timing race at the finish, not a systematic off-by-one. It can still happen
in front of an audience, so keep the SQL query ready.

**AGENTS KILLED reads 0 even though a copy was killed.** That tile only counts
chaos injected through the buttons. A Ctrl+C is invisible to it. Do not point at
that tile as evidence of the kill. Point at the two terminal windows, or the
database.

## Still to run

Modes 2, 3 and 4 in `run-modes.md`. Mode 2, Catalyst Cloud, is the one that adds
the console.

