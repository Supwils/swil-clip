# ADR-0002 — Reopen the prompt library, closed since 2026-05-28

**Date:** 2026-08-20 · **Status:** Accepted
**Reverses:** the Non-Goals entry in `version-roadmap.md`; un-deprecates
`docs/v1/prompt-manager.md`

## Context

On 2026-05-28 a prompt/snippet library was designed in full
(`docs/v1/prompt-manager.md`) and then rejected. The Non-Goals section recorded
it as never to be reconsidered — "this is another product; fork it if you want
it" — and the draft was stamped deprecated.

That deprecation notice also wrote down its own unlock condition:

> "If someone raises this again, first read this document and the Non-Goals
> section, understand why it was rejected, **then discuss whether circumstances
> have changed.**"

They have. The three original objections were:

1. *"This is another product."*
2. *"It collides head-on with Raycast."*
3. *"Would users leave us if we don't have it?"*

**All three are market arguments.** On 2026-08-20 the project stopped being a
product (ADR-0001): there are no users and no market. The objections do not
survive the change of goal — they were never about the design.

The replacement filter is two questions, and the proposal passes both:

1. **Would I actually use it?** The author's real corpus — résumé-skill
   optimisation, session handoff, job-application form filling — is reused daily
   and is currently retrieved by scrolling back through chat logs. This is
   observed behaviour, not a hypothesised need.
2. **Is the code worth reading?** A second storage tier with its own lifecycle,
   sharing an encryption and selection layer with the first, is a better work
   sample than a fifth bug fix in a frozen tree.

## Decision

The prompt library is **built**, in the Swift tree, as milestone M2 — after M1
(clipboard parity) is in daily use.

Reopened: a manually curated, long-lived prompt tier, exempt from history
eviction, in a second tab of the same panel.

**Still closed:** `{{variable}}` expansion, tags, folders, sync, AI features,
cross-platform. Nothing in the real corpus uses variables; the schema does not
preclude adding them later.

The merged-app form is load-bearing, not incidental. `⇧S` promotes the selected
clipboard entry into the library with a title derived from its first line. That
action **cannot exist** if the two are separate apps, and it is the entire
argument for putting them in one panel.

## Consequences

**Good.** Fills the gap the original Non-Goals left open: when folders and tags
were rejected, "important things get evicted by the 50-entry cap" was left with
no answer. A separate long-lived tier is that answer, without organising history.

**Bad.** The panel now has a mode. Mitigated by making it exactly one `Tab` key
with independent state per side, and by keeping the prompt record to two fields.

**Obligation.** `version-roadmap.md` and `docs/v1/prompt-manager.md` must be
updated in the same change. A repository must not simultaneously contain a
document promising "never" and a directory implementing it.
