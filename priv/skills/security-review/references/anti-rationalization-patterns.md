# Anti-Rationalization Patterns

This document catalogs common excuses agents give when taking security shortcuts and why they are invalid. Use these patterns when reviewing findings to help agents recognize and reject their own shortcuts.

## Security Anti-Rationalizations

| Excuse | Why It's Invalid | Correct Response |
| ------ | ---------------- | ---------------- |
| "This is an internal tool, security doesn't matter" | Internal tools get compromised. Attackers target the weakest link. Lateral movement starts from trusted internal surfaces. | Apply the same security controls to internal systems as to external ones. |
| "We'll add security later" | Security retrofitting is 10x harder than building it in. Adding it later means insecure foundations are already load-bearing. | Build security in from the start. Treat every external input as hostile, every secret as sacred. |
| "No one would try to exploit this" | Automated scanners find everything. Security by obscurity is not security. | Assume hostile probing. Design for adversarial conditions. |
| "The framework handles security" | Frameworks provide tools, not guarantees. Auto-escaping doesn't help if you bypass it; parameterized queries don't help if you concatenate anyway. | Verify framework security settings. Don't bypass built-in protections. |
| "It's just a prototype" | Prototypes ship to production. Security habits from day one prevent security debt from day two. | Assume the code will ship. Apply the same standards to prototypes as to production code. |
| "The data isn't sensitive" | You don't know what future use cases will be. Data becomes sensitive over time and in combination. | Treat all data with appropriate safeguards. Classify and protect accordingly. |
| "Performance comes first" | Security is a performance requirement, not an optimization. Insecure systems are unusable when breached. | Design security into the architecture. Use security-focused performance patterns. |
| "It's too much work" | Security debt is more expensive to fix later. Breaches are catastrophic in cost, reputation, and compliance. | Invest in security upfront. It's cheaper than remediation. |

## Planning Anti-Rationalizations

| Excuse | Why It's Invalid | Correct Response |
| ------ | ---------------- | ---------------- |
| "I know what to build, let's just start" | Assumptions become expensive misalignments when caught after implementation. | Surface assumptions explicitly. Get alignment on what, why, and done before coding. |
| "The requirements are clear enough" | Vague requirements lead to rework. "Faster" is not a success criterion. | Reframe vague requirements into concrete, testable conditions with metrics. |
| "We can figure out the details later" | Unknowns compound into blocked findings or architectural dead ends. | Identify unknowns explicitly. Spike research before implementation. |
| "This is a small change, no need to plan" | Small changes can have large surface area. Context matters. | Check touched layers. Even small changes may need review if they cross boundaries. |

## Code Quality Anti-Rationalizations

| Excuse | Why It's Invalid | Correct Response |
| ------ | ---------------- | ---------------- |
| "It works, that's what matters" | Working code that is unmaintainable becomes technical debt. Future changes become exponentially harder. | Write clean, maintainable code. Clarity over cleverness. |
| "I'll clean it up later" | Code cleanup rarely happens. Technical debt compounds. | Write clean code the first time. Refactor as you go. |
| "This is a temporary hack" | Temporary code becomes permanent. Hacks accumulate and rot the codebase. | Write production-quality code from the start. If you need a hack, mark it with TODO and a ticket. |
| "The tests will catch it" | Tests don't catch design flaws, security issues, or performance problems. Quality is more than test coverage. | Apply multiple quality gates: security review, performance analysis, design review. |
| "Nobody will read this code" | Future you will read this code. Others will maintain it. Code is read more than written. | Write code for humans, not just machines. Document intent. |

## Testing Anti-Rationalizations

| Excuse | Why It's Invalid | Correct Response |
| ------ | ---------------- | ---------------- |
| "I'll test it manually" | Manual testing doesn't scale. Regressions happen. Automation is necessary for confidence. | Write automated tests. Use TDD where appropriate. |
| "This is too hard to test" | Hard-to-test code is a design smell. It indicates tight coupling and hidden dependencies. | Refactor for testability. Use dependency injection. Isolate side effects. |
| "The tests are passing, it's fine" | Passing tests don't prove correctness. They only prove the tests pass. | Review test coverage. Test edge cases. Use property-based testing. |
| "I'll add tests after the feature works" | Tests after the fact are often shallow or skipped. TDD drives better design. | Write tests first or alongside code. Treat tests as part of the feature. |

## Usage in Findings

When persisting findings with `ck_finding`, include anti-rationalization context in the `plain_message` or `metadata`:

```json
{
  "category": "security",
  "severity": "warning",
  "plain_message": "Input validation missing at API boundary. Common rationalization: 'I'll add security later' — security is a constraint on every line that touches user data, not a phase.",
  "rule_id": "input-validation-required"
}
```

Including the anti-rationalization in the finding text ensures it surfaces at review time and guides the agent that reads the finding back.
