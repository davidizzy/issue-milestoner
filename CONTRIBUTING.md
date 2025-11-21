# Contributing to Issue Milestoner

Thank you for considering contributing to Issue Milestoner! This document provides guidelines and instructions for contributing to this GitHub Action.

## Table of Contents

- [Getting Started](#getting-started)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Getting Started

### Prerequisites

- GitHub CLI (`gh`) - for milestone assignment
- `jq` - for JSON parsing
- `bash` - for script execution
- Git
- A GitHub account

### Development Setup

1. **Fork and clone the repository**:

   ```bash
   git clone https://github.com/your-username/issue-milestoner.git
   cd issue-milestoner
   ```

2. **Install tools** (if not already available):

   ```bash
   brew install gh jq  # macOS
   gh auth login
   ```

3. **Verify setup**:

   ```bash
   ./tests/test-composite.sh
   ```

## Making Changes

### Code Style

- Follow existing shell script patterns
- Use meaningful variable and function names
- Add comments for complex logic
- Ensure scripts pass syntax check: `bash -n script.sh`

### Commit Messages

Write clear, descriptive commit messages following [Conventional Commits](https://www.conventionalcommits.org/):

- Use the imperative mood ("Add feature" not "Added feature")
- Start with one of these prefixes:
  - `feat:` - New features
  - `fix:` - Bug fixes
  - `docs:` - Documentation changes
  - `chore:` - Maintenance tasks, dependency updates, etc.
  - `ci:` - CI/CD pipeline changes, workflow updates
- Keep the first line under 72 characters
- Include more details in the body if needed

**Note**: Only commits with the above prefixes will trigger releases via Release Please.

Example:

```text
Add support for multiple milestone targets

- Allow comma-separated milestone names in target-milestone input
- Update logic to try each milestone until one is found
- Add validation for milestone format
- Update documentation with examples
```

## Testing

### Running Tests

```bash
./tests/test-composite.sh
```

### Local Testing with Real Data

```bash
export GH_TOKEN=your_token
./test-local.sh
```

### Test Guidelines

- Add tests for new features and bug fixes
- Ensure all tests pass before submitting a PR
- Test edge cases and error conditions

## Submitting Changes

### Pull Request Process

1. **Ensure your branch is up to date**:

   ```bash
   git checkout main
   git pull upstream main
   git checkout your-branch
   git rebase main
   ```

2. **Test your changes**:

   ```bash
   ./tests/test-composite.sh
   ```

3. **Test locally if needed**:

   ```bash
   ./test-local.sh
   ```

4. **Push to your fork**:

   ```bash
   git push origin your-branch
   ```

5. **Create a Pull Request** on GitHub with:
   - Clear title describing the change (with a conventional commit prefix)
   - Detailed description of what was changed and why
   - Reference any related issues
   - Screenshots or examples if applicable

> [!NOTE]
> If commits do not have conventional commit prefix, ensure the PR name does.
> To avoid burdening contributors, squash merging of PRs into main will be supported.

## Release Process

This project uses [Release Please](https://github.com/googleapis/release-please) for automated releases and follows semantic versioning (SemVer):

- **Patch** (0.0.x): Bug fixes and minor improvements (`fix:` commits)
- **Minor** (0.x.0): New features that don't break existing functionality (`feat:` commits)
- **Major** (x.0.0): Breaking changes (commits with `!` or `BREAKING CHANGE`)

### Automated Release Process

1. **Commit with conventional prefixes**: Use `feat:`, `fix:`, `docs:`, `chore:`, or `ci:` prefixes
2. **Release Please creates PR**: Automatically creates a release PR when commits are pushed to main
3. **Review and merge**: Maintainers review and merge the release PR
4. **Automated release**: Release Please creates a GitHub release and updates the distribution

### Manual Steps (if needed)

- Update marketplace listing for major releases
- Announce releases in relevant channels

## Key Files

- **`action.yml`** - Action definition and inputs/outputs
- **`assign-milestone.sh`** - Main logic for milestone assignment
- **`tests/test-composite.sh`** - Unit tests
- **`test-local.sh`** - Local testing with real GitHub API

## Development Guidelines

### Adding New Features

1. Check for existing issues or create one to discuss the feature
2. Update `action.yml` if adding new inputs/outputs  
3. Implement logic in `assign-milestone.sh`
4. Add tests to `tests/test-composite.sh`
5. Update README.md with usage examples

### Fixing Bugs

1. Create a test that reproduces the bug
2. Fix the issue in the shell script
3. Verify the fix with tests
4. Update documentation if needed

## Getting Help

- **GitHub Issues**: [Create an issue](https://github.com/davidizzy/issue-milestoner/issues/new) for bugs or feature requests

## Recognition

Contributors will be recognized in:

- GitHub contributors list
- Release notes for significant contributions
- README.md acknowledgments (for major features)

Thank you for contributing to Issue Milestoner! 🎯
