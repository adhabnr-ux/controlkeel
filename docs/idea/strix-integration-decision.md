# Strix Integration Decision

**Date:** 2026-05-01
**Decision:** Remove Strix integration from ControlKeel core
**Reason:** ControlKeel is open source and free; Strix introduces paid dependencies

## Background

ControlKeel is an open source governance tool available via:
- Homebrew (free)
- npm (free)
- Release installers (free)
- No billing or paid tiers mentioned

Strix is a commercial security testing tool that:
- Has a free CLI but requires LLM API keys (direct cost to users)
- Offers a paid platform (app.strix.ai) with enterprise features
- Is a funded commercial product (24.7k GitHub stars)

## Decision

**Remove Strix integration from ControlKeel core** to maintain CK's:
1. Free and open-source nature
2. No dependency on paid services
3. Local-first, no-telemetry philosophy
4. Vendor independence

## Actions Taken

### Removed
- `lib/controlkeel/agent_adapters/strix.ex` - Strix agent adapter
- `priv/skills/strix/` - Strix skill directory
- `priv/benchmarks/strix_security_detection_v1.json` - Strix benchmark suite
- `docs/idea/strix-integration-analysis.md` - Analysis document
- `docs/idea/strix-integration-summary.md` - Summary document
- Strix references from agent registry
- Strix references from test expectations
- Strix occupation (`strix_operator`) from security domain pack
- Strix-specific language from security pack guidance and questions

### Kept (Valuable Independent Enhancements)
- **OWASP Top 10** - Industry standard for web security
- **CWE/CVE standards** - Industry standard vulnerability classification
- **vulnerability_categories** - Structured taxonomy with 7 families:
  - Access Control (IDOR, privilege escalation, auth bypass)
  - Injection (SQL, NoSQL, command, LDAP)
  - Server-Side (SSRF, XXE, deserialization, path traversal)
  - Client-Side (XSS, prototype pollution, DOM, CSRF)
  - Business Logic (race conditions, workflow manipulation)
  - Authentication (JWT, session fixation, weak credentials)
  - Infrastructure (misconfigurations, exposed services)
- **CWE mappings** for each vulnerability category

These kept enhancements are:
- Based on free, open industry standards (OWASP, CWE)
- Valuable for CK's security governance independent of any tool
- No dependencies on paid services
- Aligned with CK's open-source philosophy

## Rationale

The security taxonomy enhancements are valuable because they:
1. Provide structured vulnerability classification for CK findings
2. Align with industry standards (OWASP Top 10, CWE)
3. Enable better security governance without external dependencies
4. Can be used by any security tool or workflow, not just Strix

## Future Considerations

If Strix or similar tools become open source and truly free (no LLM API costs), they could be reconsidered as optional plugins. However, any integration should:
1. Be strictly opt-in
2. Have clear cost warnings
3. Not be part of core CK distribution
4. Maintain CK's governance-first philosophy

## Verification

- All 1086 tests pass
- No Strix dependencies remain in core CK
- Security domain pack enhanced with industry standards only
- CK remains free and open source