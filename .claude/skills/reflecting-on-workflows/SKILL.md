---
name: reflecting-on-workflows
description: Use when finishing a workflow, milestone, change, or long debugging session, before archiving or closing out a task list, or when asked what was learned
---

# Reflecting on Workflows

## Overview

A reflection is worth doing only if something durable changes because of it. Summarizing what
happened is not reflection — the transcript already did that, and it is about to be discarded.

**Core principle: every lesson either gets a durable home or gets explicitly dropped.**

## The Method

### 1. Gather evidence — do not recall

Recall is biased toward the ending. Re-read the actual artifacts first:

```bash
git diff              # what actually changed vs. what you think changed
git log --oneline -10
```

Plus: the task list, the last few tool failures, and any message where the user corrected you.

### 2. Hunt contradictions, not highlights

The lessons that matter are where **reality disagreed with a confident claim**. Scan for:

- An assertion you made that turned out false
- An error whose message pointed at the wrong cause
- A step that worked only in a specific order
- Something the user corrected, especially twice
- A guardrail you assumed held and had to verify

Smooth successes teach nothing. If nothing contradicted you, say so — a short reflection is a
legitimate outcome and better than a padded one.

### 3. Route each candidate to a home

| Signal | Home |
|---|---|
| How this user wants you to work | `feedback` memory, with the why |
| Who they are, their constraints | `user` memory |
| Ongoing goal/state not in the repo | `project` memory (absolute dates) |
| A fact about the *system* being built | repo docs / design authority — not memory |
| A reusable technique across projects | a skill |
| Already in code, git history, or CLAUDE.md | **nothing** |
| True only of this session | **nothing** |

"Nothing" is the most common correct answer. Saving what the repo already records makes recall
worse, not better.

### 4. Write, then say what you dropped

One fact per memory file. Link related ones. Then state explicitly which candidates you discarded
and why — that is the part that keeps the store small enough to be useful.

## Quick Test

For each lesson: **would knowing this earlier have changed an action?** If not, drop it.
"Be more careful" fails this test. "Azure reports unregistered providers as SubscriptionNotFound"
passes it.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Narrating the session back | Extract only contradictions |
| Vague lessons ("communicate better") | Name the trigger and the action |
| System facts in memory | Those belong in repo docs |
| Saving a fixed bug | Git history has it |
| Skipping because "it went well" | Smooth sessions still hide wrong assumptions |
| Claiming a lesson you did not verify | Mark unverified things as unverified |

## Red Flags

- Reflection reads like a status report
- Every candidate got saved
- A lesson could apply to any project
- You are recalling instead of re-reading
