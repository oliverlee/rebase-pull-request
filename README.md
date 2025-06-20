# rebase-pull-request

A workflow to automate rebasing pull requests.

For developer workflows that involve single commit PRs, this action enables
multiple PRs to be automerged without the use of a merge queue. This action can
update protected branches, allowing this action to automerge PRs in a stack by
rebasing each PR sequentially.

The repository must allow write access to branches with the name
`temp-update-*`. This is used to produce a signed rebase commit.

## usage

```yml
- uses: oliverlee/rebase-pull-request@v0
  with:
    # Pull request to rebase. Either a pull request number or 'stale'.
    # 'stale': applies to pull requests targeting `base-branch` that are not up
    # to date.
    #
    # Default: stale
    pull-request: ''

    # Base branch to rebase pull requests onto.
    #
    # Default: main
    base-branch: ''

    # SSH key used to fetch the repository, passed to `actions/checkout`. Use of
    # an SSH key allows pushing to protected branches.
    #
    # see:
    # https://github.com/orgs/community/discussions/25305
    # https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys#set-up-deploy-keys
    checkout-ssh-key: ''
```


## example

### update stale PRs targeting `main` after `main` is updated
```yml
on:
  push:
    branches: [main]

jobs:
  rebase-pull-request:
    runs-on: ubuntu-latest
    permissions:
      contents: write # update branches used by pull requests
    steps:
      - uses: oliverlee/rebase-pull-request@v0
```

### update stale PRs with branch protection
```yml
on:
  push:
    branches: [main]

jobs:
  rebase-pull-request:
    runs-on: ubuntu-latest
    permissions:
      contents: write # update branches used by pull requests
    steps:
      - uses: oliverlee/rebase-pull-request@v0
        with:
          checkout-ssh-key: ${{ secrets.PR_DEPLOY_KEY }}
```

### runnable workflow to rebase pull requests onto arbitrary branches
```yml
on:
  workflow_dispatch:
    inputs:
      pull-request:
        default: ""
        description: |
          pull request number to rebase
      base-branch:
        default: "main"
        description: |
          branch to rebase onto

jobs:
  rebase-pull-request:
    runs-on: ubuntu-latest
    permissions:
      contents: write # update branches used by pull requests
      pull-requests: write # update pull request base branch
    steps:
      - uses: oliverlee/rebase-pull-request@v0
        with:
          pull-request: ${{ github.event.inputs.pull-request }}
          base-branch: ${{ github.event.inputs.base-branch }}
```
