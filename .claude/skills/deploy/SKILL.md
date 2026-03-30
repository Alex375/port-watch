---
name: deploy
description: Merge feature branch into dev, run CI, then create PR to main. Use when deploying, shipping, or merging.
user-invocable: true
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

4. **Bump the version** in `PortWatch/Info.plist` (`CFBundleShortVersionString`). Follow semantic versioning:
   - **Patch** (X.Y.Z → X.Y.Z+1): bug fixes, minor UI tweaks, refactoring with no user-visible change.
   - **Minor** (X.Y.Z → X.Y+1.0): new features, new UI sections, new detection capabilities, new settings.
   - **Major** (X.Y.Z → X+1.0.0): breaking changes, major redesigns, architecture overhauls.

   Read the current version, analyze the commits being merged (use `git log dev..feature-branch` or the diff), determine the appropriate bump level, and update the plist. Commit the bump separately with message: `vX.Y.Z — <short summary>`.

5. **Merge into `dev`:**
   ```bash
   git checkout dev
   git pull origin dev
   git merge <feature-branch> --no-ff
   git push origin dev
   ```

6. **Wait for CI on `dev`.** Use `gh run list --branch dev --limit 1 --json status,conclusion,databaseId` to poll for the latest workflow run. If CI fails, report the failure and stop.

7. **Create a PR from `dev` to `main`:**
   ```bash
   gh pr create --base main --head dev --title "<PR title>" --body "<PR body>"
   ```
   - The PR title should summarize the feature/fix.
   - Include the new version in the PR title or body.
   - The PR body should follow the standard format:
     ```
     ## Summary
     <bullet points>

     ## Test plan
     <checklist>
     ```

8. **Report the PR URL** to the user.

## Important notes

- Never force-push.
- If the merge into `dev` has conflicts, stop and ask the user to resolve them.
- If there is already an open PR from `dev` to `main`, report it instead of creating a duplicate.
- Always wait for CI to pass before creating the PR.
- The version bump MUST happen before merging to `dev`. The release workflow on `main` uses the version from `Info.plist` to create the GitHub Release tag.
