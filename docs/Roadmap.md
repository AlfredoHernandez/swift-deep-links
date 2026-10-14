# Roadmap

## Development Process

### Agent Team per Phase

Every execution phase (see `Docs/ImprovementChecklist.md` §5) is developed and validated by a dedicated agent team. Before starting a phase, spawn the appropriate agents; before closing it, run the post-phase review agents.

**Per-phase team (development + validation):**

1. **Implementation agents** — one of the following, sized to the phase:
   - `general-purpose` for broad, multi-file refactors with no strong GoF signal.
   - `design-patterns` when the phase restructures architecture (protocol hierarchies, strategy → chain-of-responsibility, adapter cleanup, etc.).
   - `swift-docs` when the phase ships new public APIs that need Apple-style Quick Help.
   - `swift-testing` when the phase adds tests alongside new code (TDD flow).
2. **Post-phase review agents (mandatory — see checklist §6):**
   - `code-review` — senior-architect review of source + tests touched in the phase.
   - `swift-testing` — coverage / flakiness / naming audit on the phase's test diff.
3. **Cleanup agent (as needed):**
   - `general-purpose` for comment cleanup after large refactors, per the user's standing preference to avoid narration comments.

**Coordination rules:**
- Agents that edit overlapping files run sequentially; read-only reviewers can run in parallel with each other or with implementation agents.
- Each agent gets a self-contained prompt with scope, context of what changed, and deliverable format — agents don't share conversation state.
- Triage findings into either (a) follow-up commits on the same phase branch before moving on, or (b) new items in `Docs/ImprovementChecklist.md` §4 if larger than a commit.
- Do not open the next phase with unreviewed work from the previous one.

**Branch convention:**
- All phase work lands on `feature/modernization` (or the current working branch) via small, single-concern commits.
- Commit messages are drafted by the `git-commit-messages` agent to keep style consistent.
- Push only after the user has tested locally (standing preference).

---

## Rate Limiting Strategies - Future Implementations

The following rate limiting strategies were removed from the current implementation but are planned for future releases:

### Token Bucket Strategy
- **Status**: Shipped in 1.3.0 as `RateLimitStrategy.tokenBucket(capacity:refillRate:)`
- **Description**: Uses a token bucket algorithm for more flexible rate limiting with burst allowances
- **Use Cases**: 
  - When burst allowances are needed (e.g., allowing 10 requests in 1 second, then 1 per second)
  - Systems that need to handle traffic spikes gracefully
  - More sophisticated rate limiting scenarios
- **Implementation Notes**: Requires token refill logic and bucket capacity management

### Strict Strategy
- **Status**: Planned for a future version
- **Description**: Enforces stricter rate limits (50% of configured limits) for high-security scenarios
- **Use Cases**:
  - High-security applications requiring extra protection
  - Development/testing environments that need stricter limits
  - Compliance scenarios with mandatory rate limiting
- **Implementation Notes**: Simple modification of existing sliding window with reduced limits

### Adaptive Strategy
- **Status**: Planned for a future version
- **Description**: Dynamically adjusts rate limits based on system load and user behavior
- **Use Cases**:
  - Systems with variable load patterns
  - User-specific rate limiting based on trust levels
  - ML-driven rate limiting optimization
- **Implementation Notes**: Requires metrics collection and adaptive algorithm implementation

### Distributed Strategy
- **Status**: Planned for a future version
- **Description**: Coordinates rate limiting across multiple app instances or services
- **Use Cases**:
  - Multi-instance applications
  - Microservices architectures
  - Cross-platform rate limiting
- **Implementation Notes**: Requires distributed coordination mechanism (Redis, etc.)

---
