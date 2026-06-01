# Autonomy and Findings

Agents are often eager to execute arbitrary shell commands and file writes. ControlKeel introduces "Bounded Autonomy" through the Findings system.

## Findings
When an agent attempts an action that violates a rule, exceeds budget, or fails a test, ControlKeel records a Finding.
- **Blocked:** The agent is halted and cannot proceed until a human intervenes or the issue is algorithmically resolved.
- **Escalated:** Human attention is requested but execution may continue in parallel.
- **Approved/Denied:** The final state of a human-gated finding.

## Review Gates
Agent plans (`ck_review_submit`) require human approval (`ck_review_feedback`) before large-scale execution. The agent is forced to poll `ck_review_status` rather than blindly proceeding. This shifts the operational model from "Autonomous and Unpredictable" to "Highly Capable but Human-Gated."

## Cost Governance
Budgets form another layer of bounded autonomy. Agents are assigned specific limits (tokens, API calls, time). If an agent burns budget unproductively (e.g., getting stuck in a bash script loop), a budget circuit-breaker is tripped, emitting a finding and pausing the run.
