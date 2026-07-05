#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-/workspace}"
DEST_DIR="${DEST_DIR:-/app/repo}"
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
  find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name 'repo' -exec cp -a {} "$DEST_DIR"/ \;
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

git push -u origin "$BRANCH"
