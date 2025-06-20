#!/bin/bash
set -aeuo pipefail

function is_ahead
{
  local commit="$1"
  local base="$2"

  [[ $base == $(git merge-base "$base" "$commit") ]]
}

function pull_requests_with_base
{
  local base="$1"

  gh pr list \
    --base "$base" \
    --json number \
    --jq ".[] | .number"
}

function pull_request_to_commit
{
  local pr="$1"

  git fetch origin "$(gh pr view "$pr" --json headRefName --jq .headRefName)" --quiet
  gh pr view "$pr" --json headRefOid --jq .headRefOid
}

function branch_to_commit
{
  local branch="$1"

  git rev-parse "$branch"
}

function stale_pull_requests
{
  local base="$1"

  pull_requests_with_base "$base" \
    | xargs -I {} bash -c '
        is_ahead "$(pull_request_to_commit "$1")" "$(branch_to_commit "$2")" ||
        echo "$1"
        ' _ {} "$base"
}

function rebase_onto
{
  local base="$1"

  git -c advice.mergeConflict=false \
    rebase --onto "$base" HEAD~1
}

function updated_commit_message
{
  set -e
  local ref="$1"

  local original_message=$(git log --format=%B -n 1 "$ref")
  local author_name=$(git log --format=%an -n 1 "$ref")
  local author_email=$(git log --format=%ae -n 1 "$ref")

  local body=$(echo "$original_message" | awk '/^[A-Za-z][A-Za-z-]*:/ {exit} {print}' | sed '$d' | sed '$d')
  local footers=$(echo "$original_message" | awk '/^[A-Za-z][A-Za-z-]*:/ {found=1} found {print}')

  local updated_footers
  if [[ $author_name != "github-actions[bot]" ]]; then
    updated_footers=$(printf "%s\nCo-authored-by: %s <%s>" \
      "$footers" \
      "$author_name" \
      "$author_email")
  else
    updated_footers="$footers"
  fi

  printf "%s\n\n%s" "$body" "$updated_footers"
}

function sign_head_commit_with_rest_api
{
  set -e

  # https://github.com/orgs/community/discussions/50055#discussioncomment-13460641
  TREE_SHA=$(git log --format=%T | head -n1)

  # Get the parent commit hash (the base we're rebasing onto)
  PARENT_SHA=$(git rev-parse HEAD~1)

  # Push to github, this creates the blobs and tree you can later access by API.
  # Github doesn't delete anything (at least not right away) when you remove the branch.
  git push origin "HEAD:temp-update-$TREE_SHA"
  git push origin ":temp-update-$TREE_SHA"

  # Create signed commit via GitHub API with original author mentioned as Co-author
  COMMIT_RESPONSE=$(gh api -X POST repos/digiboys/sel/git/commits \
    -f "message=$(updated_commit_message HEAD)" \
    -f "tree=$TREE_SHA" \
    -f "parents[]=$PARENT_SHA" \
    --jq '.sha')

  # Update local branch to match the new commit
  git fetch origin "$COMMIT_RESPONSE"
  git reset --hard "$COMMIT_RESPONSE"
}

function update_pull_request_onto
{
  local pr="$1"
  local base="$2"

  gh pr checkout "$pr" > /dev/null 2>&1
  echo "updating $(gh pr view $pr --json url --jq '.url')"

  if rebase_onto "$base"; then
    set -e
    sign_head_commit_with_rest_api
    git push origin --force-with-lease --quiet
    gh pr edit --base "$base" > /dev/null
    echo "...✅"
  else
    echo "...failed to rebase ❌"
    git rebase --abort
  fi
}

match="$1"
base="$2"

{
  case "$match" in
    stale)
      stale_pull_requests "$base"
      ;;
    *)
      echo "$match"
      ;;
  esac
} | xargs -I {} bash -c 'update_pull_request_onto "$1" "$2"' _ {} "$base"
