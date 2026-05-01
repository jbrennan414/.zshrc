# ---------- Git branch in prompt ----------

# Enable command substitution in the prompt
setopt PROMPT_SUBST

# Function to show current git branch in parentheses
git_branch_prompt() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -n "$branch" ]]; then
    echo " (${branch})"
  fi
}

# Prompt: user@host path (branch) $
# %F{green}...%f wraps text in green
PROMPT='%n@%m %~%F{green}$(git_branch_prompt)%f $ '

# ---------- Git helpers ----------

# bcu: branch clean up
# Deletes all local branches EXCEPT the currently checked-out branch
# and the remote's default HEAD branch.
bcu() {
  local default_branch current_branch
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [[ -z "$default_branch" ]]; then
    # Fallback: ask the remote directly
    default_branch=$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
  fi
  if [[ -z "$default_branch" ]]; then
    echo "bcu: could not determine default branch from origin" >&2
    return 1
  fi

  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "$current_branch" ]]; then
    echo "bcu: not on any branch (detached HEAD?)" >&2
    return 1
  fi

  local branches_to_delete
  branches_to_delete=$(git branch --format='%(refname:short)' \
    | grep -vE "^(${default_branch}|${current_branch})$")

  if [[ -z "$branches_to_delete" ]]; then
    echo "bcu: nothing to delete (default: $default_branch, current: $current_branch)"
    return 0
  fi

  echo "bcu: keeping '$default_branch' (default) and '$current_branch' (current)"
  echo "bcu: deleting the following branches:"
  echo "$branches_to_delete" | sed 's/^/  - /'
  echo
  echo -n "Proceed? [y/N] "
  read -r confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "bcu: aborted"
    return 1
  fi

  echo "$branches_to_delete" | xargs -n 1 git branch -d
}

# gpo: git push origin
# Pulls the current branch from origin, then pushes it back up.
gpo() {
  local current_branch
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "$current_branch" ]]; then
    echo "gpo: not on any branch (detached HEAD?)" >&2
    return 1
  fi

  echo "gpo: pulling origin/$current_branch..."
  git pull origin "$current_branch" || return 1

  echo "gpo: pushing to origin/$current_branch..."
  git push origin "$current_branch"
}

# gua: git update all
# Fetches origin, then pulls every local branch that has an upstream.
gua() {
  local starting_branch
  starting_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "$starting_branch" ]]; then
    echo "gua: not on any branch (detached HEAD?)" >&2
    return 1
  fi

  echo "gua: fetching origin..."
  git fetch origin --prune || return 1

  local branches
  branches=$(git branch --format='%(refname:short)')

  local branch
  for branch in ${(f)branches}; do
    # Skip if branch has no upstream configured
    if ! git rev-parse --abbrev-ref "${branch}@{upstream}" >/dev/null 2>&1; then
      echo "gua: skipping '$branch' (no upstream)"
      continue
    fi

    echo "gua: updating '$branch'..."
    if git checkout "$branch" >/dev/null 2>&1; then
      git pull --ff-only || echo "gua: could not fast-forward '$branch' (skipping)"
    else
      echo "gua: could not checkout '$branch' (skipping)"
    fi
  done

  # Return to original branch
  git checkout "$starting_branch" >/dev/null 2>&1
  echo "gua: done. Back on '$starting_branch'."
}
