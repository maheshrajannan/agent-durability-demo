# The modes you can run this demo in

> Written 2026-09-20, after Path A was proven end to end on an Intel Mac.
> Companion to `HOW_TO_RUN.md` (the plan) and `RUN_LOG.md` (what actually happened).

---

## The one idea

Two things vary. Which agent you run, and where its ledger lives. Everything else
in the system is identical in every mode.

The ledger is the workflow history: what step each account was on, written down
before the next step is taken. A cashier who writes every dollar in a ledger can
be replaced mid-shift. A cashier who counts in his head cannot.

---

## System diagram

```mermaid
%%{init: {'flowchart': {'htmlLabels': true, 'wrappingWidth': 900, 'padding': 12, 'nodeSpacing': 55, 'rankSpacing': 70}}}%%
flowchart TB
    B["<b>BROWSER</b> localhost:9000<br/>Start, Stop, Reset, the two chaos buttons"]

    M["<b>MCP SERVER</b> Docker, host port 9000<br/>serves the page, holds the queue of 1,000 tasks<br/><i>MCP = Model Context Protocol. One tool here: credit_next</i>"]

    A["<b>AGENT</b> your Mac, port 8000<br/>same graph in every mode: decide, then credit one dollar<br/><i>agent-plain | agent-langgraph | agent-dapr-agents</i>"]

    DB["<b>POSTGRES</b> Docker, port 5432<br/>accounts and transactions<br/><i>primary key (run, tx_id) is what makes a replayed step harmless</i>"]

    subgraph LED["THE LEDGER - the ONLY thing that changes between modes"]
        direction TB
        N["<b>nowhere.</b> In process memory.<br/>✅ DONE - killed at 173, stayed at 173 forever<br/><i>agent-plain. Needs nothing. This is the 'before' picture.</i>"]
        R1["<b>local Dapr.</b> Redis container on your Mac.<br/>✅ DONE - killed at 201, recovered alone, 1000 of 1000<br/><i>agent-langgraph, ONE copy. Needs the 2-line MCP_DIRECT_URL patch.</i>"]
        R2["<b>local Dapr,</b> same Redis.<br/>▶ MODE 1 - 15 min, no account<br/><i>agent-langgraph, TWO copies on 8000 and 8001. Kill the second.<br/>The run never stops. Proves failover, not just restart.</i>"]
        C["<b>Catalyst Cloud.</b> Diagrid runs the ledger.<br/>MODE 2 - 45 to 60 min, free account, untested by Claude<br/><i>Adds the console: app graph, agent page, workflow history.</i>"]
        R3["<b>local Dapr,</b> same Redis.<br/>MODE 3 - about 20 min, untested by Claude<br/><i>agent-dapr-agents. Same hardcoded URL on line 11, so the same patch works.</i>"]
        K["<b>Catalyst self-hosted.</b> Your Kubernetes cluster.<br/>MODE 4 - half a day plus a cloud bill. Skip it.<br/><i>The only mode where Pod failure and AZ failure work.</i>"]
    end

    B --> M
    M -- "schedule one workflow per account, 10 of them" --> A
    A -- "credit_next, one dollar at a time" --> M
    M -- "INSERT, ON CONFLICT DO NOTHING" --> DB
    A -- "writes every step BEFORE taking the next one" --> LED

    N ~~~ R1
    R1 ~~~ R2
    R2 ~~~ C
    C ~~~ R3
    R3 ~~~ K
```

---

## Ranked by value for your time

| Mode | What it proves that the others do not | Your time | Money | Account |
|---|---|---|---|---|
| **1. Two copies, failover** | It survives **without** a restart. A second copy takes over the dead one's accounts. | 15 min | $0 | none |
| **2. Catalyst Cloud** | The console: app graph, agent page, workflow history. This is the product. | 45-60 min | $0 free tier | Diagrid |
| **3. Dapr Agents variant** | The same durability on a second framework, not just LangGraph. | ~20 min | $0 | none |
| **4. Kubernetes self-hosted** | The Pod failure and AZ failure buttons actually work. | half a day | cloud bill | Diagrid org |

Mode 1 is the one worth doing next. Last night proved "it survives a restart".
Mode 1 proves "it survives without one", which is the claim that matters in
production. Different claim, 15 minutes, nothing to install.

Mode 4 buys two buttons whose message is already proved. The Helm chart defaults
point at the repo authors' own running environment, so asking for access costs
one message instead of half a day.

## Not a mode

Real-LLM. It is documented in `docs/CATALYST.md`, `docs/DEMO_FLOW.md` and
`scripts/switch-llm-mode.sh`, but all three agent variants raise an error when
`STUB_LLM=false`. Appendix B of `HOW_TO_RUN.md` has the detail.

## References

1. `HOW_TO_RUN.md` - Part 3.6 is Mode 1, Part 4 is Mode 2, Part 6 is Mode 4.
2. `services/agent-dapr-agents/agent_worker/mcp_client.py` line 11 - the hardcoded
   Catalyst URL that Mode 3 needs patched, identical to the agent-langgraph one.
3. `RUN_LOG.md` - the two DONE boxes in the diagram, with real numbers.
