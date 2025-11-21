# Issue Milestoner

A GitHub Action that automatically assigns issues to milestones based on specified criteria.

## Features

- ✅ Assigns issues to target milestones
- ✅ Prevents reassignment if issue already has a milestone
- ✅ Optional issue type filtering using GitHub issue types ([only available for org-based repos](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/managing-issue-types-in-an-organization))
- ✅ Optional label filtering using issue labels
- ✅ Comprehensive logging and error handling
- ✅ Configurable for any repository

## Usage

### Basic Usage

```yaml
- name: Assign Issue to Milestone
  uses: davidizzy/issue-milestoner@v1.1.2 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
```

### Advanced Usage with Issue Type Filter

```yaml
- name: Assign Bug Issues to Milestone
  uses: davidizzy/issue-milestoner@v1.1.2 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
    issue-type: "bug"  # GitHub issue type
```

### Advanced Usage with Label Filter

```yaml
- name: Assign Enhancement Issues to Milestone  
  uses: davidizzy/issue-milestoner@v1.1.2 # x-release-please-version
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    issue-number: ${{ github.event.issue.number }}
    target-milestone: "my-important-milestone"
    issue-label: "enhancement"  # Issue label
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
        uses: davidizzy/issue-milestoner@v1.1.2 # x-release-please-version
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
| `issue-label` | Optional issue label filter (e.g., enhancement, documentation, ui) | No | - |
| `repository` | Repository in the format owner/repo | No | Current repository |

## Outputs

| Output | Description |
|--------|-------------|
| `assigned` | Whether the issue was assigned to the milestone (true/false) |
| `milestone` | The milestone that was assigned |
| `reason` | Reason for the action taken or not taken |

## Behavior

1. **Milestone Check**: If the issue already has a milestone assigned, the action will not reassign it
2. **Issue Type Filtering**: If `issue-type` is provided, the action checks if the issue's GitHub issue type matches (case-insensitive)  
3. **Label Filtering**: If `issue-label` is provided, the action checks if any issue label matches the specified filter (case-insensitive)
4. **Milestone Matching**: The action finds the target milestone by name (case-insensitive)
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
This workflow automatically assigns issues labeled with "enhancement" to a "Wishlist" milestone, demonstrating real-world usage of the `issue-label` filtering feature.

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
