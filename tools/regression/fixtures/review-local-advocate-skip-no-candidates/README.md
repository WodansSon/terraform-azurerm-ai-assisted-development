# Sanitized Fixture: Local Review Skip Path For Review Advocate This fixture is synthetic and sanitized. It exists to prove the generic local review prompt does not invoke the advocate second pass when the primary review produces no candidate Issues. ## Scenario Two AI-toolkit files change together: - `.github/skills/review-advocate/SKILL.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md` The edits are benign wording alignment only. They do not introduce contradictory rules, stale paths, output-contract drift, or missing shipped-payload wiring. ## Simplified Change Shape - The skill wording is clarified to match the contract terminology.
- The contract wording is clarified without changing the deterministic outcome mapping.
- No prompt text, hard-stop text, or manifest wiring is changed. ## Expected Review Behavior A correct local code review should: - Apply the AI-customization review scope because the change is under `.github/skills/` and `.github/instructions/`
- Conclude that the change introduces no candidate Issues
- Skip the advocate second pass entirely
- Produce no `Skill used: review-advocate` verification marker
- Produce no `[⚖️ ADVOCATE:...]` annotation because no finding was dismissed ## Expected Must-Catch Outcomes - `advocate-skip-when-no-candidate-issues` ## Expected Must-Not-Flag Outcomes - `spurious-review-advocate-marker`
