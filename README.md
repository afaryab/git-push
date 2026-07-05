# git-push

A small Docker image that copies files from a mounted directory into a Git repository, initializes Git, commits the changes, and pushes them to a remote repository using a GitHub token.

## Usage

### Build the image

```bash
docker build -t your-docker-user/git-push .
```

### Run the container

The image already contains the current build context under `/workspace`, so no bind mount is required for the default flow.

```bash
docker run --rm \
  -e GIT_TOKEN="your_github_token" \
  -e GITHUB_REPOSITORY="owner/repo" \
  your-docker-user/git-push
```

### Run with Docker Compose

Create a `.env` file with:

```env
GIT_TOKEN=your_github_token
GITHUB_REPOSITORY=owner/repo
GIT_BRANCH=main
COMMIT_MESSAGE=chore: sync from container
```

Example compose file:

```yaml
services:
  git-push:
    image: ahmadfaryabkokab/git-push:latest
    volumes:
      - ./workspace:/workspace
    environment:
      GIT_TOKEN: ${GIT_TOKEN}
      GITHUB_REPOSITORY: ${GITHUB_REPOSITORY:-owner/repo}
      GIT_BRANCH: ${GIT_BRANCH:-main}
      COMMIT_MESSAGE: ${COMMIT_MESSAGE:-chore: sync from container}
```

Then run:

```bash
docker compose up --build
```

### Environment variables

- `GIT_TOKEN`: GitHub token used for HTTPS authentication.
- `GITHUB_REPOSITORY`: Repository in the form `owner/repo`.
- `GIT_REMOTE_URL`: Optional full remote URL. If provided, it overrides `GITHUB_REPOSITORY`.
- `SOURCE_DIR`: Source directory to copy from. Defaults to `/workspace`.
- `DEST_DIR`: Destination repository directory. Defaults to `/app/repo`.
- `GIT_BRANCH`: Branch to push to. Defaults to `main`.
- `COMMIT_MESSAGE`: Commit message. Defaults to `chore: sync from container`.
- `GIT_USER_NAME`: Git author name. Defaults to `GitHub Actions`.
- `GIT_USER_EMAIL`: Git author email. Defaults to `actions@github.com`.

## GitHub Actions deployment

This repository includes a workflow that builds and pushes the image to Docker Hub whenever changes are pushed to `main`.

### Required GitHub secrets

Add these secrets in your repository settings:

- `DOCKER_USERNAME`: your Docker Hub username
- `DOCKER_PASSWORD`: your Docker Hub access token or password

The workflow uses the Docker Hub credentials to publish the image as `ahmadfaryabkokab/git-push`.

## Notes

- The container clears the destination directory before copying the mounted content.
- The script will skip the push if there are no file changes to commit.
