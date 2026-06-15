![issue-milestoner](https://socialify.git.ci/davidizzy/issue-milestoner/image?description=1&language=1&name=1&owner=1&pattern=Formal+Invitation&theme=Auto)

# Issue Milestoner

A GitHub Action that automatically assigns issues to a milestone, gated by GitHub
**issue type** or **label**. It's most useful for organization repositories using
GitHub issue types, and for sharing one milestone-automation step across many
repositories with a consistent, versioned contract.

## Do you even need this?

For a single repository doing simple label-based assignment, maybe not — native
workflow gating plus two lines of `gh` cover it:

```yaml
- name: Assign to milestone if unset
  if: contains(github.event.issue.labels.*.name, 'enhancement')
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    n=${{ github.event.issue.number }}
    has=$(gh issue view "$n" --json milestone --jq '.milestone.title // ""')
    [ -z "$has" ] && gh issue edit "$n" --milestone "Wishlist"
```

This action earns its keep when you want:

- **Issue-type gating** (`issue-type`) — GitHub issue types aren't cleanly
  expressible in workflow `if:` conditions, so this is the awkward case to do by hand.
- **One reusable, versioned step** shared across many repositories, with consistent
  outputs (`assigned` / `milestone` / `reason`) and built-in API retries.

If neither applies, the inline snippet above is simpler to own and debug.

## Features

- ✅ Assigns issues to a target milestone (resolved case-insensitively)
- ✅ Prevents reassignment if the issue already has a milestone
- ✅ Optional issue-type filtering using GitHub issue types ([only available for org-based repos](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/managing-issue-types-in-an-organization))
- ✅ Optional label filtering (exact label match, case-insensitive)
- ✅ Comprehensive logging and error handling
- ✅ Configurable for any repository

## Migrating from v1

- **Breaking — `issue-label` now matches the exact label** (case-insensitive), not a
  substring. In v1, `issue-label: ui` also matched a label like `build`, and `bug`
  matched `debugging`, which could assign milestones unexpectedly. Set `issue-label`
  to the exact label name; if you relied on partial matching across several labels,
  use one action step per label.
- **Improved (non-breaking) — `target-milestone` resolves case-insensitively** against
  your repository's real milestones (e.g. `wishlist` finds `Wishlist`), as documented.

## Usage

### Filter by issue type (the primary use case)

GitHub issue types are awkward to gate on in a workflow `if:` condition — this is
where the action is most worthwhile. Only assigns issues whose type matches:

```yaml
- name: Assign Bug Issues to Milestone
  uses: davidizzy/issue-milestoner@v2.0.0 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
    issue-type: "bug"  # GitHub issue type (org repos only)
```

### Filter by label

Only assigns issues carrying the exact label (case-insensitive):

```yaml
- name: Assign Enhancement Issues to Milestone
  uses: davidizzy/issue-milestoner@v2.0.0 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
    issue-label: "enhancement"  # exact label match
```

### No filter

Assigns the milestone to any issue that doesn't already have one:

```yaml
- name: Assign Issue to Milestone
  uses: davidizzy/issue-milestoner@v2.0.0 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
```

### Workflow Example

```yaml
name: Auto Milestone Assignment

on:
  issues:
    types: [opened, typed]

permissions:
  issues: write
  contents: read

jobs:
  assign-milestone:
    runs-on: ubuntu-latest
    steps:
      - name: Assign to Current Sprint
        uses: davidizzy/issue-milestoner@v2.0.0 # x-release-please-version
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          issue-number: ${{ github.event.issue.number }}
          target-milestone: "Unscheduled Features"
          issue-type: "feature"  # Only assign feature type issues
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | GitHub token with repository access | Yes | - |
| `issue-number` | Issue number to process | Yes | - |
| `target-milestone` | Target milestone to assign to the issue | Yes | - |
| `issue-type` | Optional GitHub issue type filter (e.g., bug, feature, task) | No | - |
| `issue-label` | Optional exact label filter, case-insensitive (e.g., enhancement, documentation) | No | - |
| `repository` | Repository in the format owner/repo | No | Current repository |

## Outputs

| Output | Description |
|--------|-------------|
| `assigned` | Whether the issue was assigned to the milestone (true/false) |
| `milestone` | The milestone that was assigned |
| `reason` | Reason for the action taken or not taken |

## Behavior

1. **Milestone Check**: If the issue already has a milestone assigned, the action will not reassign it
2. **Issue Type Filtering**: If `issue-type` is set, the issue's type must match (case-insensitive). Issues with no type (non-org repos) are skipped, not failed.
3. **Label Filtering**: If `issue-label` is set, the issue must carry a label equal to the filter (exact match, case-insensitive)
4. **Milestone Matching**: `target-milestone` is resolved against the repo's existing milestones by name (case-insensitive); the canonical title is used
5. **Assignment**: Only assigns the milestone if all conditions are met

## Permissions

The GitHub token needs the following permissions:

- `issues: write` - to update issue milestones
- `metadata: read` - to read repository information

## Limitations & Considerations

- **Rate Limits**: Subject to GitHub API rate limits (5000/hour for authenticated requests)
- **Permissions**: Requires `issues: write` and `contents: read`
- **Performance**: Optimized for issues with up to 100 labels
- **Dependencies**: Requires GitHub CLI (gh) v2.0.0+ and jq v1.6+

## Troubleshooting

### Common Issues

#### "Milestone not found"

- Verify milestone exists: `gh api repos/{owner}/{repo}/milestones`
- Check spelling (matching is case-insensitive)
- Ensure milestone is open

#### "Permission denied"

- Verify workflow has `issues: write` permission
- Check token has repository access
- Ensure you're not in a fork without secrets

## Reference Implementation

This repository includes a working example of the action in [`.github/workflows/auto-milestone-wishlist.yaml`](.github/workflows/auto-milestone-wishlist.yaml).
This workflow automatically assigns issues labeled "enhancement" to a "Wishlist" milestone, demonstrating real-world usage of the `issue-label` filtering feature.

Note how it layers a workflow-level `if:` (an efficiency gate that avoids spinning up a
runner for non-enhancement issues) with the action's own `issue-label` filter (which
enforces the label for `workflow_dispatch` runs). For a simple single-repo setup you'd
typically pick just one — see [Do you even need this?](#do-you-even-need-this) above.

You can use this as a template for creating your own milestone automation workflows.

## Development

This is a **composite action** using shell scripts for simplicity and maintainability.

### Quick Start

```bash
# Clone and test
git clone https://github.com/davidizzy/issue-milestoner.git
cd issue-milestoner
./tests/test-composite.sh

# Local testing (requires GitHub CLI and token)
export GH_TOKEN=your_token
./test-local.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed development guidelines.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing & Support

- **Contributing**: See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines
- **Issues**: [Create an issue](https://github.com/davidizzy/issue-milestoner/issues/new) for bugs or feature requests
