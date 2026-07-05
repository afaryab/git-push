#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-/workspace}"
# Default destination: if not overridden, place repo under the workspace (e.g. /workspace/repo).
DEST_DIR="${DEST_DIR:-${SOURCE_DIR}/repo}"
REMOTE_URL="${GIT_REMOTE_URL:-}"
REPOSITORY="${GITHUB_REPOSITORY:-${GIT_REPOSITORY:-}}"
BRANCH="${GIT_BRANCH:-main}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-chore: sync from container}"
GIT_USER_NAME="${GIT_USER_NAME:-GitHub Actions}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-actions@github.com}"

if [ -z "${GIT_TOKEN:-}" ]; then
  echo "GIT_TOKEN is required for HTTPS authentication." >&2
  exit 1
fi

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if [ -d "$DEST_DIR" ]; then
  find "$DEST_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

if [ -d "$SOURCE_DIR" ] && [ "$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
  # Copy or move top-level items from SOURCE_DIR to DEST_DIR.
  # Set MOVE_FILES=true to remove files from the source (useful for moving mounted files into the repo).
  while IFS= read -r -d $'\0' entry; do
    name=$(basename "$entry")
    if [ "$name" = ".git" ] || [ "$name" = "repo" ]; then
      continue
    fi
    if [ "${MOVE_FILES:-false}" = "true" ]; then
      if command -v rsync >/dev/null 2>&1; then
        # Use rsync to move while preserving attributes and removing source files.
        rsync -a --remove-source-files "$entry" "$DEST_DIR"/
        # If the source was a directory and is now empty, remove it.
        if [ -d "$entry" ] && [ -z "$(ls -A "$entry")" ]; then
          rmdir "$entry" 2>/dev/null || true
        fi
      else
        # Fallback: copy then remove the source (works across filesystems)
        cp -a "$entry" "$DEST_DIR"/
        rm -rf "$entry"
      fi
    else
      cp -a "$entry" "$DEST_DIR"/
    fi
  done < <(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -print0)
fi

cd "$DEST_DIR"

if [ -z "$REMOTE_URL" ]; then
  if [ -n "$REPOSITORY" ]; then
    REMOTE_URL="https://github.com/${REPOSITORY}.git"
  else
    echo "Set GIT_REMOTE_URL or GITHUB_REPOSITORY to define the target repository." >&2
    exit 1
  fi
fi

# Normalize supported remote URL formats to HTTPS without embedded credentials
case "$REMOTE_URL" in
  https://*/*)
    ;; # already HTTPS
  git@github.com:*)
    REMOTE_URL="https://github.com/${REMOTE_URL#git@github.com:}"
    ;; # convert SSH-style to HTTPS
  *)
    echo "Unsupported REMOTE_URL format: $REMOTE_URL" >&2
    exit 1
    ;;
esac

if [ ! -d .git ]; then
  git init -b "$BRANCH"
fi

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

git remote remove origin >/dev/null 2>&1 || true
git remote add origin "$REMOTE_URL"

git add .

if git diff --cached --quiet; then
  echo "No changes detected; nothing to push."
  exit 0
fi

git commit -m "$COMMIT_MESSAGE"

push_with_bearer() {
  GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= \
        -c http.extraheader="AUTHORIZATION: Bearer ${GIT_TOKEN}" \
        push -u origin "$BRANCH"
}

push_with_token_header() {
  GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= \
        -c http.extraheader="AUTHORIZATION: token ${GIT_TOKEN}" \
        push -u origin "$BRANCH"
}

# Try Bearer header first, fall back to token header, then to GIT_ASKPASS if needed
if push_with_bearer; then
  echo "Push succeeded using Bearer header."
elif push_with_token_header; then
  echo "Push succeeded using token header."
else
  echo "Header auth failed; trying GIT_ASKPASS fallback..." >&2
  ASK_PASS_SCRIPT=$(mktemp)
  cat > "$ASK_PASS_SCRIPT" <<'EOF'
#!/usr/bin/env sh
echo "$GIT_TOKEN"
EOF
  chmod +x "$ASK_PASS_SCRIPT"

  # Ensure origin contains a username to trigger password prompt handling by GIT_ASKPASS
  # e.g. https://github.com/owner/repo.git -> https://x-access-token@github.com/owner/repo.git
  ORIGIN_URL="$REMOTE_URL"
  ORIGIN_WITH_USER="${ORIGIN_URL/https:\/\//https://x-access-token@}"
  git remote set-url origin "$ORIGIN_WITH_USER"

  GIT_ASKPASS="$ASK_PASS_SCRIPT" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= push -u origin "$BRANCH" || {
      echo "Push failed with all auth methods." >&2
      rm -f "$ASK_PASS_SCRIPT"
      exit 1
    }

  rm -f "$ASK_PASS_SCRIPT"
  echo "Push succeeded using GIT_ASKPASS fallback."
fi
