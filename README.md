# gh-milestone-branch

A [GitHub CLI](https://cli.github.com) extension that lists the head branches of a milestone: the branches of the milestone's pull requests (any state) that are not the base branch of another PR of the same milestone. For a stack of PRs, this is the tip of each stack.

## Install

```sh
gh extension install <user>/gh-milestone-branch
# or, from a local clone:
gh extension install .
```

The command is named after the repository: `gh milestone-branch`. For the short form `gh mb`, add an alias:

```sh
gh alias set mb milestone-branch
```

## Usage

```sh
gh milestone-branch branch "<milestone>"                 # or: gh mb branch ...
gh milestone-branch switch "<milestone>" <new-branch>    # or: gh mb switch ...
```

- `branch` prints one head branch per line. Only the 200 most recent matching PRs are considered.
- `switch` creates `<new-branch>` from the milestone's head branch and switches to it (`git switch -c`). It starts from the local branch, or from `origin/<branch>` if it only exists there. Nothing is pushed. It fails if the milestone has no head branch, several head branches (they are listed), or if the branch exists neither locally nor on `origin`.

## Tests

```sh
bash tests/test.sh   # requires jq
```
