---
name: deploy
description: Use when the user asks to deploy, ship, release, merge to dev/main, or when all work on a feature/fix branch is complete and ready to be integrated. Also activate proactively when a task is finished and the user says something like "c'est bon", "go", "envoie", "push ça", or "on déploie".
user_invocable: true
---

# Deploy Skill

Automates the full deployment pipeline: feature branch -> dev -> PR to main.

## Steps

1. **Identify the current branch.** It must be a feature or fix branch (not `dev` or `main`). If on `dev` or `main`, abort with a message.

2. **Commit any uncommitted changes** on the current branch (ask the user for a commit message if there are changes).

3. **Run tests locally** before merging:
   ```bash
   xcodebuild -scheme PortWatch test
   ```
   If tests fail, report the failures and stop. Do not merge broken code.

4. **Merge into `dev`:**
   ```bash
   git checkout dev
   git pull origin dev
   git merge <feature-branch> --no-ff
   git push origin dev
   ```

5. **Wait for CI on `dev`.** Use `gh run list --branch dev --limit 1 --json status,conclusion,databaseId` to poll for the latest workflow run. If CI fails, report the failure and stop.

6. **Create a PR from `dev` to `main`:**
   ```bash
   gh pr create --base main --head dev --title "<PR title>" --body "<PR body>"
   ```
   - The PR title should summarize the feature/fix.
   - The PR body should follow the standard format:
     ```
     ## Summary
     <bullet points>

     ## Test plan
     <checklist>
     ```

7. **Report the PR URL** to the user.

## Important notes

- Never force-push.
- If the merge into `dev` has conflicts, stop and ask the user to resolve them.
- If there is already an open PR from `dev` to `main`, report it instead of creating a duplicate.
- Always wait for CI to pass before creating the PR.
