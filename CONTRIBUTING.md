# Contributing to Terraform AzureRM AI-Assisted Development

Thank you for your interest in contributing! This is a community-maintained project.

## How to Contribute

1. **Report issues**: Found a bug or confusing behavior? Open an issue with details.
2. **Suggest improvements**: Have ideas for better prompts/instructions/skills? Share them.
3. **Submit pull requests**: Installer, docs, and workflow improvements are welcome.
4. **Share examples**: Add examples that help other contributors succeed.

## Contribution Guidelines

This repo is primarily:

- An installer (PowerShell + Bash) and file manifest
- A distribution mechanism for `.github/` content (prompts, instructions, and skills)
- CI workflows validating markdown/scripts and release bundles

When in doubt, keep changes scoped and easy to review.

### What to change (common areas)

- **Installer**: [installer/](installer/) and [installer/modules/](installer/modules/)
- **AI prompts**: [.github/prompts/](.github/prompts/)
- **AI instructions**: [.github/instructions/](.github/instructions/)
- **AI skills**: [.github/skills/](.github/skills/)
- **CI workflows**: [.github/workflows/](.github/workflows/)

### Pull request expectations

- Use the PR template: [.github/pull_request_template.md](.github/pull_request_template.md)
- Prefer clear PR titles; use the repo’s title prefix conventions when applicable.
- Link related issues using closing keywords (for example `Fixes #1234`).
- If your change is user-visible, update [CHANGELOG.md](CHANGELOG.md).
- If AI/LLM assistance was used, disclose it in the PR.

### Testing and validation

The level of testing depends on what you change:

- If you expose or change behavior in PowerShell or Bash, ensure the other installer matches the new behavior to avoid cross-platform installer drift.

- **PowerShell**: run the script(s) you touched in a clean PowerShell session where possible.
- **Bash**: run the script(s) you touched in a Bash environment where possible.
- **Installer flows**: validate the command(s) you changed end-to-end.

If you cannot test locally, explain what you did validate and what prevented full testing.

### Bootstrap vs release-bundle usage

- **Bootstrap** is intended for contributors working from a git clone.
- **Release bundle install** is intended for end users.

If you update bootstrap behavior or messaging, keep it consistent across PowerShell and Bash.

### Style and quality

- Keep changes minimal and self-explanatory.
- Prefer consistent terminology across docs and help output.
- Avoid adding new concepts/flags unless they are clearly justified.
- Keep a community-friendly tone in prompts and documentation.

## Code of Conduct

Be respectful, constructive, and helpful. We're all here to improve Terraform development.
