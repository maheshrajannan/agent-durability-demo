# How to run the Bank Creditor demo

Written 2026-09-18 for commit `4f6c6c3`. Your checkout is identical to `diagrid-labs/agent-durability-demo` main on that date.

All commands are for the macOS Terminal. Run them from the repo root unless a step says otherwise. The command blocks have no `#` comments on purpose. The default macOS shell (zsh) does not treat `#` as a comment when you paste.

This guide adds two files to the repo: `HOW_TO_RUN.md` and `local/mcp-direct.patch`. It changes nothing else.

---

## 1. What you are running

Ten agents each credit one bank account from $100 to $200, one dollar at a time. That is 1,000 transactions. You break things while it runs. The claim is that every account still ends at exactly $200, with exactly 1,000 transactions.

An everyday picture. A plain agent is a cashier who counts in his head. If he faints, the count is gone. A durable agent is a cashier who writes every dollar in a ledger. If he faints, the next cashier opens the ledger and continues from the last line. In this demo the ledger is the Dapr (Distributed Application Runtime) Workflow history. Diagrid Catalyst is the hosted service that keeps that ledger for you.

MCP means Model Context Protocol. It is the standard way an agent calls tools. Here the only tool the agent calls is `credit_next`.

```
 Browser -> http://localhost:9000
    |
    v
+--------------------------------+   tool calls   +---------------------------+
| MCP server   (Docker, :9000)   |<---------------| Agent   (your Mac, :8000) |
|  - serves the web page         |                |  one of three variants    |
|  - Start / Stop / Reset        |--- schedule -->|                           |
|  - hands out the 1,000 tasks   |                +-------------+-------------+
+---------------+----------------+                              |
                |                                               | workflow state
                v                                               v
+--------------------------------+                +---------------------------+
| Postgres     (Docker, :5432)   |                | The ledger                |
|  accounts + transactions       |                |  plain agent : none       |
+--------------------------------+                |  local Dapr  : Redis      |
                                                  |  Catalyst    : Diagrid    |
                                                  +---------------------------+
```

The three agent variants live in `services/`:

| Folder | What it is | What it needs |
|---|---|---|
| `agent-plain` | LangGraph only. Nothing durable. This is the "before" picture. | Nothing |
| `agent-langgraph` | The same graph, run as a durable Dapr Workflow. This is the main demo. | Catalyst, or local Dapr plus a 3-line patch |
| `agent-dapr-agents` | The same demo built with the Dapr Agents framework. | Catalyst. Not covered here. |

---

## 2. Pick a path

| Path | What you get | Your time | Money | Accounts | Did I test it? |
|---|---|---|---|---|---|
| **A. Laptop, no account.** Parts 0, 1, 2, 3, 5. | The web page, the failure "before", the recovery "after", latency and error chaos. | 30 to 40 min | $0 | None | Yes. See Appendix A. |
| **B. Laptop plus Catalyst Cloud.** Parts 0, 1, 2, 4, 5. | Everything in A, plus the Catalyst console: app graph, agent page, workflow history. That console is the product. | 45 to 60 min more | $0 on the free tier | Diagrid | No. It needs the `diagrid` command-line tool and a login, which I do not have. |
| **C. Kubernetes plus Catalyst Self-Hosted.** Part 6. | The full stage demo. It is the only path where the "Pod failure" and "AZ failure" buttons work. AZ means Availability Zone. | Half a day or more | A cloud cluster billed by the hour | Diagrid organization with self-hosted regions | No |

**Recommendation: do path A today, then path B.** Parts 0 to 2 are shared, so nothing is wasted. Path A is the one I ran end to end, so it should work the first time. Path B is assembled from documents and has one open risk, explained in Part 4. Do path C only when you must present the stage version. The chart defaults point at an existing deployment run by the repo authors (load balancer label `demo-prod-catalyst-agents`, Catalyst project `resiliency-demo-langgraph`). Borrowing that environment costs less than building your own.

```
Part 0 -> Part 1 -> Part 2 --+--> Part 3  (no account, tested)  --+--> Part 5 -> Part 8
 check     start     "before"  |                                  |    chaos     clean up
           the base            +--> Part 4  (Catalyst Cloud)    --+
```

If you only care about Catalyst, skip Part 3.

---

## Part 0. Check your tools (5 min)

I could not see what is installed on your Mac. The bridge I work through is a Linux shell, not macOS. Run this once:

```bash
docker --version
docker compose version
docker info --format '{{.ServerVersion}}'
uv --version
lsof -nP -iTCP:5432 -iTCP:8000 -iTCP:9000 -sTCP:LISTEN
```

What you want to see:

- Three Docker lines with version numbers. If `docker info` fails, Docker Desktop is not running. Start it.
- A `uv` version. uv is the Python package and environment manager this repo uses. If it is missing, run `brew install uv`.
- No output from `lsof`. Output means another program already uses port 5432, 8000 or 9000. A local Postgres on 5432 is the usual one. `brew services list` shows its name. Stop it with `brew services stop` and that name.

Python itself is not a prerequisite. `uv sync` downloads a suitable Python if you do not have 3.11 or newer.

The web page loads React and Babel from `unpkg.com` every time it opens. unpkg is a CDN (content delivery network). Your browser needs internet access, or the page stays blank.

---

## Part 1. Start the database, the MCP server and the web page (5 to 10 min)

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml up -d --build
docker compose -f local/compose.yaml ps
curl -s http://localhost:9000/healthz
open http://localhost:9000
```

The first build takes a few minutes. Expected results:

- `ps` shows `postgres` as healthy and `mcp` as running.
- `curl` prints `{"status":"ok"}`.
- The browser shows "Bank Creditor Demo", ten accounts at $100.00, and a **Start run** button.

Do not press Start yet. There is no agent to do the work. That comes next.

If the balances are not $100, old data is in the Docker volume. Click **Reset**.

---

## Part 2. The "before" picture: a plain agent loses its work (5 min)

Open a second Terminal tab.

```bash
cd ~/git/agent-durability-demo/services/agent-plain
uv sync
MCP_URL=http://localhost:9000/mcp/ uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

macOS may ask whether Python can accept incoming connections. Click Allow. The MCP container calls back into this process.

Now in the browser:

1. Click **Reset**, then **Start run**. Balances climb fast. This variant has no pacing, so the whole run takes about a minute.
2. After 20 to 30 seconds, press `Ctrl+C` in the agent tab. The balances stop.
3. Start the agent again with the same `uv run` command. The balances stay frozen. The new process knows nothing about the old run. The cashier fainted and the count is gone.
4. Click **Stop run**, then **Reset**. Press `Ctrl+C` in the agent tab. The next part needs port 8000.

One thing to know. The agent tiles may still say "alive" after you kill the process. The page infers "alive" from the run state, not from the process. Watch the balances and the "Transactions processed" counter instead. They stop.

In my test the plain agent was killed at 487 of 1,000. It stayed at 487 after the restart.

---

## Part 3. The "after" picture with no account: durable agent on local Dapr (15 min)

This follows `docs/LOCAL_DAPR.md`. The repo authors call it a debugging recipe, not a supported deployment. It is still the fastest way to see durable execution, and I ran it end to end.

### 3.1 Install Dapr

```bash
brew install dapr/tap/dapr-cli
dapr init --runtime-version 1.18.2
dapr --version
docker ps --format '{{.Names}}' | grep dapr_
```

Docker must be running. Expected: CLI (command-line interface) and runtime versions, then `dapr_placement`, `dapr_scheduler`, `dapr_redis` and `dapr_zipkin`. Version 1.18.2 is the one the repo authors tested and the one I tested.

### 3.2 Apply the 3-line patch

The durable agent has the Catalyst tool-call address hard-coded. The patch adds one optional setting, `MCP_DIRECT_URL`, so the agent can call the MCP server directly. With the setting absent, the code behaves exactly as before.

```bash
cd ~/git/agent-durability-demo
git apply local/mcp-direct.patch
git diff --stat
```

Expected: one file changed, `services/agent-langgraph/agent_worker/mcp_client.py`, 3 insertions and 2 deletions.

### 3.3 Run the durable agent

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
uv sync
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8000 -H 3500 -G 50001 -M 9091 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8000
```

Wait for these lines:

```
Registering workflow 'dapr.langgraph.Banker.workflow' with runtime
Registered node: agent
Registered node: tools
runner started (stub=True)
```

`STUB_LLM=true` means the agent uses a fixed decision function, not a real LLM (large language model). No model key is needed. Do not set it to false. The code refuses to start in that mode.

### 3.4 Kill it and watch it recover

1. In the browser click **Reset**, then **Start run**. This variant is paced at one credit per account every 0.3 seconds. A full run takes about 2 minutes.
2. Mid-run, press `Ctrl+C` in the agent tab. Everything exits within a few seconds. The balances freeze.
3. Wait 10 seconds so the freeze is visible.
4. Start the agent again with the same `dapr run` command. **Do not press Start.** Start means "new run" and resets every balance to $100.
5. Within 10 to 20 seconds the balances climb again, from where they stopped. Every account finishes at $200.00.

For a harsher kill, run this from another tab instead of `Ctrl+C`:

```bash
pkill -9 -f "agent_worker.main:app"; pkill -9 -x daprd
```

You need both halves. The first half also kills the `dapr run` launcher, because its command line contains the same text. That leaves the sidecar process `daprd` orphaned and still holding ports 3500 and 50001. The second half removes it. I tested `Ctrl+C` and this harsh kill. Both recover the same way.

### 3.5 Prove the invariant

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml exec postgres psql -U bankadmin -d bankdemo -c \
  "SELECT execution_run_id, COUNT(*), SUM(amount) FROM transactions GROUP BY 1 ORDER BY 1 DESC LIMIT 3;"
```

This is a SQL (Structured Query Language) count per run. The durable run shows `1000` and `1000.00`. The plain run from Part 2 shows a smaller number. That contrast is the demo.

### 3.6 Optional: failover without a restart

This is the closest laptop match to "a pod dies and a healthy pod takes over". Open a third tab and start a second copy on different ports:

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
STUB_LLM=true MCP_DIRECT_URL=http://localhost:9000/mcp/ \
  dapr run --app-id bank-agent-creditor --app-port 8001 -H 3501 -G 50002 -M 9092 \
  -- uv run uvicorn agent_worker.main:app --host 0.0.0.0 --port 8001
```

Start a run, then press `Ctrl+C` in the tab of the **second** copy (port 8001). The run keeps going. Accounts owned by the dead copy pause for a few seconds, then the first copy picks them up. Stop the second copy, not the first. The Start and Stop buttons talk to port 8000.

### 3.7 Undo the patch when you are done

```bash
cd ~/git/agent-durability-demo
git checkout -- services/agent-langgraph/agent_worker/mcp_client.py
```

The patch does nothing unless `MCP_DIRECT_URL` is set, so it does not interfere with Part 4. Just do not commit it.

---

## Part 4. The "after" picture on Catalyst Cloud (45 to 60 min)

**I have not run this part.** It is assembled from `docs/CATALYST.md`, the Diagrid documentation, and Diagrid's own `catalyst-quickstarts` repo. I changed three things from `docs/CATALYST.md`. Each change is backed by the code or by an official quickstart:

| `docs/CATALYST.md` says | This guide uses | Why |
|---|---|---|
| App identity `agent-worker` | `bank-agent-creditor` | `dapr.yaml` runs the agent under `bank-agent-creditor`. The grant must name the identity that really calls. |
| Grant tools `get_balance,credit_account,get_next_task,report_done` | `credit_next` | Those four tools no longer exist. I listed the live tools: `list_customers`, `get_customer`, `credit_next`. The agent calls only `credit_next`. |
| "Known gap": Catalyst Cloud cannot reach `localhost:9000`. It suggests ngrok. | The `diagrid dev run` tunnel | Diagrid's `mcp-auth` quickstart exposes a local MCP server by listing it as a second app with an `appPort`. The run command then opens a tunnel to that port. |

If you try ngrok or cloudflared anyway, the MCP server rejects the request with status 421 "Invalid Host header". I reproduced that. The server only accepts `localhost` style host names.

```
 Agent (Mac, :8000) --tool call--> Catalyst Cloud MCP proxy --dev-run tunnel--> localhost:9000 (MCP in Docker)
        ^                                  |
        +---- workflow steps and state ----+
```

**Time-box: if step 4.5 is not working after 20 minutes, stop.** Part 3 already gives you the durability story. The remaining unknowns are on the Catalyst side, and the repo authors are the fastest source for those.

### 4.1 Account and command-line tool

Sign up at https://catalyst.diagrid.io. The Diagrid docs say Catalyst Cloud is free to start. Then:

```bash
cd ~/Downloads
curl -o- https://downloads.diagrid.io/cli/install.sh | bash
sudo mkdir -p /usr/local/bin
sudo mv ./diagrid /usr/local/bin/
diagrid version
diagrid login
diagrid whoami
```

`diagrid login` opens a browser. If no browser opens, go to https://login.diagrid.io/activate and type the code from the terminal.

### 4.2 Project and agent identity

```bash
diagrid project create bank-creditor-local \
  --enable-managed-workflow \
  --enable-agent-infrastructure \
  --use --wait
diagrid agent create bank-agent-creditor --wait
diagrid agent list
```

Pass both flags now. The repo docs say agent infrastructure cannot be added to a project later. I left out the region flag that `docs/CATALYST.md` uses, so the project lands in your organization's default region. Provisioning takes a few minutes. Expected: the agent shows as ready.

### 4.3 Register the MCP server and grant the tool

```bash
cd ~/git/agent-durability-demo
cat > local/catalyst-mcpserver.yaml <<'EOF'
apiVersion: dapr.io/v1alpha1
kind: MCPServer
metadata:
  name: bank-postgres-mcp
spec:
  endpoint:
    streamableHTTP:
      url: http://localhost:9000/mcp/
EOF
diagrid apply -f local/catalyst-mcpserver.yaml
diagrid mcpserver access grant bank-postgres-mcp \
  --caller bank-agent-creditor \
  --allow-tools credit_next --wait
```

The name `bank-postgres-mcp` matters. The agent looks for that name by default. A new MCP server denies every caller until you grant access.

### 4.4 Create the run file with two apps

The first app is the agent, copied from `dapr.yaml`. The second app runs a do-nothing command. It exists only so the run command opens a tunnel from Catalyst Cloud to port 9000, where Docker publishes the MCP server.

```bash
cd ~/git/agent-durability-demo
cat > dapr-catalyst-local.yaml <<'EOF'
version: 1
common:
  appLogDestination: console
  daprdLogDestination: console
  enableAppHealthCheck: false
  logLevel: info
apps:
  - appID: bank-agent-creditor
    appDirPath: ./services/agent-langgraph
    daprHTTPPort: 3500
    appPort: 8000
    appProtocol: http
    command: ["uv", "run", "uvicorn", "agent_worker.main:app", "--host", "0.0.0.0", "--port", "8000"]
    env:
      STUB_LLM: "true"
      LOG_LEVEL: INFO
  - appID: bank-postgres-mcp
    appDirPath: ./local
    appPort: 9000
    appProtocol: http
    command: ["tail", "-f", "/dev/null"]
EOF
```

The do-nothing command is my adaptation. The official quickstart starts a real MCP process there. I kept the MCP server in Docker so the web page stays up while you kill the agent. This is the least certain line in the guide.

### 4.5 Run

Part 1 must be up. Stop the agents from Parts 2 and 3 first. Port 8000 must be free.

```bash
cd ~/git/agent-durability-demo/services/agent-langgraph
uv sync
cd ~/git/agent-durability-demo
diagrid dev run --file dapr-catalyst-local.yaml --project bank-creditor-local --approve \
  --skip-managed-kv --skip-managed-pubsub --skip-default-resiliency
```

If the tool rejects a flag, run `diagrid dev run --help` and drop that flag. The flags come from the repo docs and the official quickstarts.

Two checkpoints before you press Start:

1. The agent log shows `Registered node: agent`, `Registered node: tools` and `runner started (stub=True)`.
2. Catalyst can reach the MCP server. In another tab run `docker compose -f local/compose.yaml logs -f mcp`. Per the official quickstart, Catalyst probes a registered MCP server as soon as its tunnel is up. You should see `POST /mcp` lines with `200 OK`.

To test the grant alone:

```bash
diagrid mcpserver access test bank-postgres-mcp --caller bank-agent-creditor --tool credit_next
```

### 4.6 Run the demo

Click **Reset**, then **Start run**. Expect it to be slower than Part 3. Every step goes to Diagrid's cloud and every tool call comes back through the tunnel.

Open https://catalyst.diagrid.io and pick the project. `docs/DEMO_FLOW.md` sections 1 to 3 and 7 walk through the console: the app graph, the `banker` agent page, and the workflow history.

### 4.7 Kill and recover

1. Mid-run, run `pkill -9 -f "agent_worker.main:app"` in another tab. The balances freeze. The web page stays up because it lives in Docker.
2. If `diagrid dev run` is still running, press `Ctrl+C` in its tab.
3. Run the same `diagrid dev run` command again. **Do not press Start.** The workflows live in Catalyst, not in the process you killed. They resume on their own.

### 4.8 Tear down

```bash
diagrid dev stop -f dapr-catalyst-local.yaml
diagrid project delete bank-creditor-local
```

---

## Part 5. Chaos buttons on a laptop

| Button | Works on a laptop? | What happens |
|---|---|---|
| **MCP Latency: 10s** | Yes | Every tool call takes 3 extra seconds for 10 seconds. The credit rate drops, then recovers. |
| **MCP tool call failure** | Yes | The next tool call fails. The workflow retries that step. The account is still credited exactly once. |
| **Pod failure** | No, greyed out | It deletes real Kubernetes pods. The laptop equivalent is killing the agent process (3.4, 3.6, 4.7). |
| **AZ failure** | No, greyed out | It needs a cluster spread across zones. |

I tested both working buttons against the durable agent. The run still ended at 1,000 transactions and $200 in every account.

Laptop coverage of `docs/DEMO_FLOW.md`: sections 4, 5, 6 (partly) and 8 work on paths A and B. Sections 1, 2, 3 and 7 need the Catalyst console, so path B only. The real-LLM "what-if" at the end of that file does not work. See Appendix B.

---

## Part 6. Kubernetes plus Catalyst Self-Hosted (summary only)

Follow `docs/CATALYST_SELF_HOSTED.md` steps 1 to 9. Use `docs/DEPLOYMENT.md` steps 0 to 2 for node labels and images. You need `kubectl`, `helm`, the `diagrid` tool, a cluster, and a Diagrid organization that can create self-hosted regions. The authors used AKS (Azure Kubernetes Service).

Things the documents do not make obvious. I checked each one against the charts and the code:

- **You need at least two nodes.** The charts pin Postgres and MCP to `bank-creditor.role=platform` and the agents to `bank-creditor.role=agents`. One node cannot carry both values of the same label. Without the labels the pods stay Pending. On a one-node cluster, pass `--set nodeSelector=null` to each chart.
- **Zone spread blocks scheduling on clusters without zone labels.** On kind, k3s or minikube add `--set topologySpread.enabled=false` to the agent chart.
- **The Postgres chart defaults to storage class `managed-csi`.** That class exists only on AKS. Override `persistence.storageClassName` elsewhere.
- **You may not need to build images.** The chart defaults pull `alicejgibbons/bank-creditor-mcp:0.1.0` and `alicejgibbons/bank-creditor-agent:0.1.0`. Try `docker pull` on one. If it works, skip the build step.
- **The tool grant is `credit_next`.** `docs/CATALYST_SELF_HOSTED.md` step 8 has this right.
- **`CLAUDE.md` says to set `dapr.enabled=false` under Catalyst. The overlay in step 6 does not set it.** Adding `dapr: {enabled: false}` to the overlay matches the stated intent. This is my reading, not something I tested.
- **Do not run `scripts/switch-llm-mode.sh real`.** See Appendix B.
- **The MCP service defaults to a public load balancer with an Azure DNS (Domain Name System) label.** On a local cluster use `--set service.type=ClusterIP` and `kubectl -n bank-creditor port-forward svc/mcp 8080:80`.

---

## Part 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| The web page is blank | The browser cannot reach `unpkg.com` | Use a network that allows it. The browser console shows the blocked files. |
| `port is already allocated` on `compose up` | Another program uses 5432 or 9000 | Run the `lsof` line from Part 0 and stop that program. |
| Start run does nothing | The MCP container cannot reach the agent on port 8000 | Check `curl localhost:8000/healthz`. Keep `--host 0.0.0.0`. Allow the macOS firewall prompt. Then run `docker compose -f local/compose.yaml logs mcp` and look for `schedule ... failed`. |
| Balances are odd at the start | Old data in the Docker volume | Click **Reset**. For a clean slate run `docker compose -f local/compose.yaml down -v`, then Part 1 again. |
| "MCP Server Calls" panel looks empty | The browser window is too short and the panel collapses | Make the window taller, or zoom out with Cmd and minus. I reproduced this at 950 pixels of height. |
| Everything reset after a kill | You pressed Start. Start means "new run". | To resume, only restart the agent. |
| `dapr run` fails on state store or actors | `dapr init` was not run, or the Dapr containers are stopped | Run `docker ps` and look for `dapr_`. Run `dapr init` again. |
| `dapr run` says port 3500 or 50001 is in use | An orphaned `daprd` from an earlier kill | Run `pkill -9 -x daprd`, then start the agent again. |
| Catalyst: tool calls return `403` | The grant is missing or names another caller | Run the grant in 4.3 again. Check with `diagrid mcpserver access get bank-postgres-mcp`. |
| Catalyst: `404` on `/v1.0/diagrid/mcp/...` | Per the official quickstart this means "caller matches no rule", not "not found" | Same fix as `403`. Also check the server name is exactly `bank-postgres-mcp`. |
| MCP log shows `Invalid Host header: X` (status 421) | The MCP server only trusts `localhost` style host names | In `local/compose.yaml`, under the `mcp` service `environment:`, add `MCP_ALLOWED_HOSTS: "localhost,localhost:9000,127.0.0.1,127.0.0.1:9000,X"`. Then run `docker compose -f local/compose.yaml up -d`. |
| Catalyst: Python certificate error | Python is not reading the system certificates | In `services/agent-langgraph` run `uv run python -m certifi`. Export the printed path as `SSL_CERT_FILE`, then run 4.5 again. |
| Catalyst: `RESOURCE_EXHAUSTED` in the agent log | Catalyst Cloud rate-limits each app identity (`CLAUDE.md`) | Run fewer accounts: `curl -X POST localhost:9000/agent/spawn -H 'Content-Type: application/json' -d '{"customers":3,"credits_per_customer":100,"target":200}'` |
| `No module named 'mcp.server.fastmcp'` | An old checkout without the `mcp<2.0.0` pin | Pull the latest commit. Yours already has the pin. |

`docs/TROUBLESHOOTING.md` covers the Kubernetes failures.

---

## Part 8. Clean up

```bash
cd ~/git/agent-durability-demo
docker compose -f local/compose.yaml down -v
git checkout -- services/agent-langgraph/agent_worker/mcp_client.py
dapr uninstall
```

`down -v` also deletes the demo data. `dapr uninstall` is optional. For Catalyst, see 4.8.

---

## Appendix A. What I tested, and how

I ran this commit in a Linux sandbox on 2026-09-18. There was no Docker daemon there. So I ran Postgres 16 directly, ran the MCP server and the agents with `uv` on Python 3.11, and ran Dapr 1.18.2 in slim mode with a Postgres state store instead of the default Redis. I did not run the Docker packaging or anything on macOS. I read `local/compose.yaml`, and I simulated the dependency step of the MCP Dockerfile. It installs cleanly.

| Test | Result |
|---|---|
| Plain agent, killed at 487 of 1,000, then restarted | Stayed at 487. Progress lost. |
| Durable agent, two copies, one killed at 304 | The other copy finished. 1,000 transactions. All ten accounts at $200. |
| Durable agent, one copy, `kill -9` at 185, down 15 seconds, restarted | Frozen at 185 while down. Resumed alone. Finished at 1,000. |
| Durable agent, `Ctrl+C` at 780, restarted | Everything exited in 3 seconds. Resumed alone. Finished at 1,000. |
| Durable agent, the harsh kill command from 3.4 at 147, restarted | Resumed within 10 seconds. |
| Plain agent, `Ctrl+C` mid-run | Exited in 2 seconds. Frozen at 133. |
| Durable agent with one forced tool failure and 3 seconds of latency for 10 seconds | One activity failed and was retried. Finished at 1,000. |
| SQL check from 3.5 | Durable runs: count 1000, sum 1000.00. Plain run: count 487. |
| Web page in headless Chromium | Rendered. Start run worked. Balances ticked. Pod and AZ buttons were greyed out. |
| Request to `/mcp/` with a foreign Host header | Status 421, "Invalid Host header". |
| `local/mcp-direct.patch` on a clean checkout of `4f6c6c3` | Applies and reverts cleanly. |

Not tested: Part 4, Part 6, Docker on macOS, and the Homebrew installs.

## Appendix B. Where the repo documents and the code disagree

1. `docs/CATALYST.md` creates app identity `agent-worker`. `dapr.yaml` uses `bank-agent-creditor`.
2. `docs/CATALYST.md` and section 2 of `docs/DEMO_FLOW.md` describe four tools: `get_next_task`, `get_balance`, `credit_account`, `report_done`. `services/mcp/mcp_server/server.py` now has one consolidated tool, `credit_next`, plus two read-only tools.
3. Real-LLM mode is documented in `docs/CATALYST.md`, `docs/DEMO_FLOW.md`, `scripts/switch-llm-mode.sh` and `deploy/agent/values.yaml`. All three agents raise an error when `STUB_LLM=false`. The script would put the agent pods into a crash loop. `CLAUDE.md` does say real mode is unsupported.
4. `README.md` lists `services/agent/`. The real folders are `agent-langgraph`, `agent-dapr-agents` and `agent-plain`.
5. `docs/DEMO_FLOW.md` talks about 100 agents and 4 agent pods. The current design is 10 long-running workflows, one per account. The agent chart defaults to 2 replicas.
6. `docs/CATALYST.md` says the run command starts a local sidecar. The Diagrid docs say it injects `DAPR_HTTP_ENDPOINT`, `DAPR_GRPC_ENDPOINT` and `DAPR_API_TOKEN` into your process. `main.py` handles both cases.

## Sources

- Repo files: `README.md`, `CLAUDE.md`, `dapr.yaml`, `local/compose.yaml`, `local/init.sql`, everything under `docs/`, `services/` and `deploy/`, and `ui-prototype/src/telemetry.jsx`, `panels.jsx`, `shell.jsx`.
- Diagrid docs: [CLI install](https://docs.diagrid.io/catalyst/references/cli-reference/intro), [agents quickstart](https://docs.diagrid.io/getting-started/quickstarts/ai-agents/), [projects](https://docs.diagrid.io/operate/platform-operations/projects/), [operator quickstart](https://docs.diagrid.io/operate/getting-started/), [MCP overview](https://docs.diagrid.io/develop/mcp/), [add an MCP server](https://docs.diagrid.io/develop/mcp/mcpserver-getting-started/), [MCP servers in a project](https://docs.diagrid.io/operate/project-operations/mcp-servers/), [MCP authentication](https://docs.diagrid.io/develop/mcp/mcp-authentication/), [connectivity](https://docs.diagrid.io/operate/hosting/connect/), [troubleshooting](https://docs.diagrid.io/references/troubleshooting/).
- Diagrid quickstarts repo, https://github.com/diagridio/catalyst-quickstarts : `mcp-auth/python` for the tunnel pattern, `agents/langgraph` for the run-file format and the kill and restart flow.
