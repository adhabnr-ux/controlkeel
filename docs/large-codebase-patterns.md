# Large Codebase Patterns for Governed AI

This document synthesizes insights from Anthropic's "Claude Code at scale" series and ControlKeel's governance experience to provide patterns for successful AI coding agent deployment in large codebases.

## What counts as a "large codebase"

"Large codebase" encompasses a wide range of deployments:
- Monorepos with millions of lines of code
- Legacy systems built over decades
- Dozens of microservices across separate repositories
- Distributed architectures spanning hundreds of repositories
- Codebases in languages not traditionally associated with AI tools (C, C++, C#, Java, PHP)

The patterns here generalize across these environments and serve as a starting point for teams adopting governed AI agents at scale.

## Agentic search vs RAG-powered approaches

### The RAG approach and its limitations

Traditional RAG-powered AI coding tools work by:
- Embedding the entire codebase into vector representations
- Retrieving relevant chunks at query time
- Maintaining a centralized index that must be kept up-to-date

**At large scale, RAG systems face critical failure modes:**
- Embedding pipelines cannot keep pace with active engineering teams
- By the time a developer queries the index, it reflects the codebase as it existed weeks, days, or hours prior
- Retrieval returns functions that were renamed, modules that were deleted, or patterns that have evolved
- No indication that retrieved content is stale or out-of-date

### The agentic search advantage

Claude Code (and similar agentic systems) navigate codebases the way a software engineer would:
- Traverse the file system directly
- Read files on-demand
- Use grep/find to locate exactly what's needed
- Follow references across the codebase
- Operate locally on the developer's machine with live codebase access

**Key benefits:**
- No embedding pipeline to maintain
- No centralized index that becomes stale
- Each developer's instance works from the current codebase state
- No delay between code changes and search availability

### The tradeoff

Agentic search works best when the agent has enough starting context to know where to look. This means:
- Quality of navigation is shaped by codebase setup
- Layering context with CLAUDE.md files and skills is essential
- Asking an agent to find vague patterns across a billion-line codebase will hit context limits
- Teams that invest in codebase setup see significantly better results

**ControlKeel alignment:** CK's virtual workspace and progressive discovery patterns align with agentic search principles, avoiding stale embedding pipelines while maintaining governed exploration.

## The harness matters as much as the model

A common misconception is that agent capabilities are defined solely by the model's benchmark performance. In practice, the ecosystem built around the model—the harness—determines actual performance more than the model alone.

### The extension hierarchy

The harness is built from layered extension points, each serving distinct functions:

#### 1. CLAUDE.md files (context foundation)
- **What:** Context files that agents read automatically at session start
- **When:** Every session, regardless of task
- **Best for:** Project-specific conventions, codebase knowledge, critical gotchas
- **Load pattern:** Additive as agent moves through directory tree (root → subdirectories)
- **Common mistake:** Using it for reusable expertise that belongs in skills

**Best practices:**
- Keep root CLAUDE.md lean: pointers and critical gotchas only
- Use subdirectory CLAUDE.md files for local conventions
- Everything else drifts into noise in large codebases
- Update every 3-6 months as model intelligence evolves

#### 2. Hooks (continuous improvement)
- **What:** Scripts that run at key moments (start, stop, pre-edit, post-edit)
- **When:** Triggered by specific events
- **Best for:** Automating consistent behavior, capturing session learnings
- **Common mistake:** Using prompts for things that should run automatically

**Valuable hook patterns:**
- **Stop hooks:** Reflect on what happened during session, propose CLAUDE.md updates while context is fresh
- **Start hooks:** Load team-specific context dynamically for module-specific setups
- **Automated checks:** Enforce linting, formatting, validation deterministically for consistency

#### 3. Skills (on-demand expertise)
- **What:** Packaged instructions for specific task types or workflows
- **When:** On-demand, when relevant to the task
- **Best for:** Reusable expertise across sessions and projects
- **Load pattern:** Progressive disclosure—only load when task calls for it
- **Common mistake:** Loading everything into CLAUDE.md instead

**Skill capabilities:**
- Path scoping: Bind skills to specific directories so they only activate in relevant code sections
- Domain specialization: Security review skill loads for vulnerability assessment, document processing skill for documentation updates
- Workflow encapsulation: Complex multi-step processes packaged as reusable workflows

**Example:** A payments team can bind their deployment skill to the payments service directory, preventing auto-loading when developers work elsewhere in the monorepo.

#### 4. Plugins (distribution mechanism)
- **What:** Bundled skills, hooks, and MCP configurations in installable packages
- **When:** Always available once configured
- **Best for:** Distributing working setups across organization
- **Common mistake:** Letting good setups stay tribal knowledge

**Plugin benefits:**
- New engineers install plugin and immediately have same context/capabilities as experienced team members
- Updates distributed through managed marketplaces
- Enables organizational consistency without manual configuration

**Real-world example:** A retail organization built a skill connecting Claude to their internal analytics platform for business analysts, then distributed it as a plugin before broad rollout.

#### 5. Language Server Protocol (LSP) integrations (symbol-level precision)
- **What:** Real-time code intelligence via language-specific servers
- **When:** Always available once configured
- **Best for:** Symbol-level navigation, automatic error detection in typed languages
- **Common mistake:** Assuming it's automatic

**LSP benefits:**
- Gives agents same navigation as developers in IDEs
- Symbol-level precision: follow function calls to definitions, trace references across files
- Distinguish between identically named functions in different languages
- Without LSP: agents pattern-match on text and can land on wrong symbols

**Enterprise impact:** One software company deployed LSP integrations org-wide before Claude Code rollout specifically to make C and C++ navigation reliable at scale. For multi-language codebases, this is one of the highest-value investments.

#### 6. MCP servers (external connectivity)
- **What:** Connections to external tools, data sources, and APIs
- **When:** Always available once configured
- **Best for:** Giving agents access to internal tools they can't otherwise reach
- **Common mistake:** Building MCP connections before basics work

**Sophisticated MCP patterns:**
- Structured search as a direct tool call
- Internal documentation integration
- Ticketing system connections
- Analytics platform access

#### 7. Subagents (exploration/editing separation)
- **What:** Separate agent instances with own context windows for specific tasks
- **When:** When invoked
- **Best for:** Splitting exploration from editing, parallel work
- **Common mistake:** Running exploration and editing in same session

**Subagent patterns:**
- Read-only subagent maps subsystem and writes findings to file
- Main agent edits with full picture from findings
- Parallel subagents for independent exploration tasks
- Fresh context windows avoid contamination between phases

### Extension layer summary

| Component | What it is | When it loads | Best for | Common confusion |
|-----------|-------------|--------------|----------|------------------|
| CLAUDE.md | Context file auto-read | Every session | Project conventions, codebase knowledge | Using for reusable expertise (belongs in skills) |
| Hooks | Scripts at key moments | Triggered by events | Automated behavior, session learnings | Using prompts for automatic things |
| Skills | Packaged task instructions | On-demand when relevant | Reusable expertise across sessions | Loading everything into CLAUDE.md |
| Plugins | Bundled skills/hooks/MCP | Always available once configured | Distributing setups across org | Letting good setups stay tribal |
| LSP | Real-time code intelligence | Always available once configured | Symbol-level navigation in typed languages | Assuming it's automatic |
| MCP servers | External tool/data connections | Always available once configured | Internal tool access | Building before basics work |
| Subagents | Separate agent instances | When invoked | Split exploration from editing | Running exploration/editing together |

*LSP accessed through plugin layer. Subagents are delegation capability, not configured extension point.*

## Configuration patterns for large codebases

### Making codebases navigable at scale

Agent effectiveness in large codebases is bounded by ability to find right context. Too much context degrades performance; too little leaves agent navigating blind. Successful deployments invest upfront in making codebases legible.

#### Pattern 1: Keep CLAUDE.md files lean and layered

**Implementation:**
- Root file: pointers and critical gotchas only
- Subdirectory files: local conventions and module-specific guidance
- Agent loads additively as it moves through directory tree
- Root-level context is never lost when working in subdirectories

**Why it matters:**
- Prevents context bloat from loading unnecessary information
- Ensures relevant guidance is available where needed
- Scales to hundreds of directories without performance degradation

#### Pattern 2: Initialize in subdirectories, not at repo root

**Implementation:**
- Start agent work in specific subdirectory relevant to task
- Agent automatically walks up directory tree loading CLAUDE.md files
- Root-level context is still available through hierarchical loading

**Why it matters:**
- In monorepos, this may feel counterintuitive since tooling assumes root access
- Scopes agent to part of codebase actually relevant to task
- Reduces unnecessary context loading from unrelated modules

**ControlKeel alignment:** CK's workspace context and progressive discovery support this pattern naturally.

#### Pattern 3: Scope test and lint commands per subdirectory

**Implementation:**
- CLAUDE.md files at subdirectory level specify commands for that part of codebase
- Avoid running full suite when agent changed one service
- Works well for service-oriented codebases with per-directory build commands

**Challenges:**
- In compiled-language monorepos with deep cross-directory dependencies, per-subdirectory scoping is harder
- May require project-specific build configurations
- Sometimes full build is necessary due to dependency chains

#### Pattern 4: Use .ignore files for generated files and build artifacts

**Implementation:** This is a Claude Code native feature, not a CK feature.

- Commit `.claude/settings.json` exclusion rules in version control
- Exclude generated files, build artifacts, third-party code
- Every developer gets same noise reduction without individual configuration

CK manages only its own `.gitignore` entry (`/controlkeel`) to exclude its data directory from version control. For broader file exclusions affecting agent exploration, configure Claude Code's `settings.json` directly.

**Edge cases:**
- In some codebases, generated files are subject of development work
- Developers working on code generators can override project-level exclusions locally
- Does not affect rest of team

#### Pattern 5: Build codebase maps when directory structure doesn't help

**Implementation:**
- For non-standard directory structures, create lightweight markdown at repo root
- List each top-level folder with one-line description of contents
- Gives agent table of contents to scan before opening files

**Layered approach for very large codebases:**
- Root file describes only highest-level structure
- Subdirectory CLAUDE.md files provide next level of detail
- Load on-demand as agent moves through tree

**Alternative for simpler cases:**
- @-mention specific files or directories agent should reference
- Achieves same result without full codebase map

#### Pattern 6: Run LSP servers for symbol-level search

**Implementation:**
- Install code intelligence plugin for your language
- Install corresponding language server binary
- Configure agent to use LSP for navigation

**Why it matters:**
- Grep for common function name in large codebase returns thousands of matches
- Agent burns context opening files to figure out which matters
- LSP returns only references pointing to same symbol
- Filtering happens before agent reads anything

**ControlKeel alignment:** CK's virtual workspace performs filesystem-level exploration (grep, find, read). LSP integration is a Claude Code and IDE-native capability; configure language servers through your IDE or Claude Code extension, not through CK.

### Active CLAUDE.md maintenance

As models evolve, instructions written for current models can work against future ones:

**Examples of evolution:**
- CLAUDE.md rule guiding Claude through patterns it struggled with may become unnecessary
- Rules preventing newer model capabilities can actively constrain performance
- Instruction to break refactor into single-file changes may have helped earlier model but prevents newer one from making coordinated cross-file edits

**Skills and hooks evolution:**
- Built to compensate for specific model limitations
- Become overhead once limitations no longer exist
- Example: hook enforcing p4 edit in Perforce became redundant when Claude Code added native Perforce mode

**Maintenance cadence:**
- Meaningful configuration review every 3-6 months
- Additional review when performance plateaus after major model releases
- Remove constraints that newer models handle well
- Add guidance for emerging failure patterns

## Organizational patterns for enterprise adoption

Technical configuration alone doesn't drive successful adoption. Organizations that succeed invest in organizational layer too.

### Infrastructure investment before broad access

**Pattern:** Dedicated infrastructure investment before broad rollout

**Examples:**
- Small team (sometimes one person) wires tooling so agent fits developer workflows
- At one company: couple engineers built suite of plugins and MCPs available on day one
- At another: entire team focused on managing AI coding tools had infrastructure in place before rollout

**Result:** Developers' first experience is productive rather than frustrating, adoption spreads from there

**Team placement:**
- Typically sits under Developer Experience or Developer Productivity
- Responsible for onboarding new engineers and building developer tooling

### Emerging role: Agent manager

**Role definition:** Hybrid PM/engineer function dedicated to managing AI agent ecosystem

**Responsibilities:**
- Ownership over agent configuration
- Authority to make calls on settings, permissions policy
- Management of plugin marketplace
- CLAUDE.md conventions
- Keeping everything current

**Minimum viable version:** DRI (Directly Responsible Individual) with same scope

### Avoiding tribal knowledge fragmentation

**Bottoms-up adoption challenge:** Generates enthusiasm but can fragment without centralization

**Requirements:**
- Individual or team to assemble and evangelize right conventions
- Standardized CLAUDE.md hierarchy
- Curated set of skills and plugins
- Centralized knowledge management

**Without this work:**
- Knowledge stays tribal
- Adoption plateaus
- Inconsistent configurations across teams

### Governance for regulated industries

**Common questions in large organizations:**
- Who controls which skills and plugins are available?
- How to prevent thousands of engineers from independently rebuilding same thing?
- How to ensure AI-generated code goes through same review process as human-generated code?

**Recommended approach:**
- Start with defined set of approved skills
- Required code review processes
- Limited initial access
- Expand as confidence builds

**Cross-functional working groups:**
- Bring together engineering, information security, governance representatives
- Define requirements together
- Build rollout roadmap
- Establish governance frameworks early

## Applying these patterns to your organization

### Assumptions and scope

These guidance patterns assume:
- Conventional software engineering environments
- Engineers as primary codebase contributors
- Git-based version control
- Standard directory structures

**Most large codebases fit this mold**, but non-traditional setups require additional configuration:
- Game engines with large binary assets
- Environments with unconventional version control
- Non-engineers contributing to codebase

For non-traditional setups, additional configuration work is required. This is where Applied AI teams work directly with engineering organizations to translate patterns into specific requirements.

## ControlKeel-specific guidance

### How CK complements these patterns

**Agentic search alignment:**
- CK's virtual workspace supports live codebase exploration
- Progressive discovery avoids stale embedding pipelines
- Governed exploration maintains security boundaries

**Extension hierarchy integration:**
- CK skills align with Anthropic's skill pattern
- CK hooks support continuous improvement patterns
- CK's governance layer adds validation to extension loading

**Large codebase configuration:**
- CK's project-local binding supports subdirectory scoping
- Adaptive tool groups optimize context loading
- Workspace snapshots enable efficient large codebase navigation

**Organizational governance:**
- CK's domain packs support regulated industry requirements
- Findings and proofs provide audit trails
- Budget management controls cost at scale

### CK-specific large codebase recommendations

**1. Layer CK governance with agent capabilities:**
- Use CK validation for agent-generated code
- Leverage CK findings for continuous improvement
- Integrate CK proofs into agent workflow documentation

**2. Govern extension distribution:**
- Use CK plugin system for skill distribution
- Validate skills through CK's review process
- Track skill usage and effectiveness through CK metrics

**3. Scale validation appropriately:**
- Use CK's scoped validation for subdirectory-specific rules
- Leverage CK's domain packs for industry-specific requirements
- Implement CK's budget controls for cost management at scale

**4. Organizational integration:**
- Map CK governance to existing code review processes
- Use CK findings to inform CLAUDE.md maintenance
- Integrate CK's observability into agent performance monitoring

## Related documentation

- [agent-integrations.md](agent-integrations.md): Host-specific integration patterns
- [getting-started.md](getting-started.md): Initial setup and configuration
- [code-mode-governance.md](code-mode-governance.md): Code execution governance
- [observability-feedback-loop.md](observability-feedback-loop.md): Production monitoring patterns
- [AGENTS.md](../AGENTS.md): Project-specific governance requirements