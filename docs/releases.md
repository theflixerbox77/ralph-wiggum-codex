# Releases

This repo should use GitHub Releases, not GitHub Packages, as its primary shipping surface.

## Why Releases

This repository currently ships:
- two Codex skills
- a shell runner script
- documentation and tests

That maps cleanly to GitHub Releases:
- each release points at a git tag
- GitHub automatically provides source zip and tarball downloads for that tag
- release notes can summarize what changed in the skills and runner

GitHub Packages is not a good fit yet because the repo does not currently publish a package artifact such as:
- an npm package
- a Python package
- a Ruby gem
- a container image
- a GitHub Action

If this repo later grows a packageable install target, GitHub Packages can be revisited. For now, Releases are the right mechanism.

## Release Order

For this repo, the order should be:

1. Commit the release-ready changes to `main`.
2. Push `main`.
3. Create an annotated tag for that exact commit.
4. Push the tag.
5. Create a GitHub Release from the tag.

The release is not itself a commit. It is metadata attached to a git tag, and the tag points at a commit.

## Versioning Policy

Use pre-1.0 semantic versioning for now:
- `v0.x.0` for meaningful feature or workflow milestones
- `v0.x.y` for fixes, docs corrections, and release-note cleanup

Do not jump to `v1.0.0` until the public skill contracts are intentionally stable.

### Starting Point

The recommended first release for the current history is `v0.8.0`.

Why `v0.8.0`:
- the project is well past an initial prototype
- there are already multiple substantive development milestones in git history
- the interfaces are still evolving enough that `v1.0.0` would overstate stability

## Suggested Workflow

### Commit and push

```bash
git checkout main
git pull --ff-only
git add .
git commit -m "Prepare v0.8.0 release"
git push origin main
```

### Create and push the tag

```bash
git tag -a v0.8.0 -m "Release v0.8.0"
git push origin v0.8.0
```

### Create the GitHub Release

With GitHub CLI:

```bash
gh release create v0.8.0 \
  --repo MattMagg/ralph-wiggum-codex \
  --title "v0.8.0" \
  --notes-file CHANGELOG.md
```

For real use, prefer trimming the release notes to the section for the tag you are publishing.

## Notes For Future Releases

- Update `CHANGELOG.md` before tagging.
- Tag the exact commit that is already on `main`.
- Keep release notes focused on user-visible changes to the two skills, the runner, and installation/use patterns.
- Treat GitHub Packages as out of scope unless the repo gains a real package artifact.
