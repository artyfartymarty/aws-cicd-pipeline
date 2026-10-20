"""Tests for the release scripts in scripts/ci/, run on throwaway git repos.

Each test builds the history it needs (main, dev, squash commits, release
merges) in a temp directory and runs the real script against it.
"""

import os
import subprocess
from pathlib import Path

import pytest

CI = Path(__file__).resolve().parent.parent


def git(repo, *args):
    return subprocess.run(
        ["git", *args], cwd=repo, check=True, capture_output=True, text=True
    ).stdout.strip()


def commit(repo, message):
    """An empty commit stands in for a squash-merged PR on dev."""
    git(repo, "commit", "-q", "--allow-empty", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def release(repo):
    """Merge dev into main with a merge commit, like the release PR does."""
    git(repo, "checkout", "-q", "main")
    git(repo, "merge", "-q", "--no-ff", "dev", "-m", "Merge pull request #1 from me/dev")
    git(repo, "checkout", "-q", "dev")
    return git(repo, "rev-parse", "main")


def run(repo, script, *args, env=None):
    return subprocess.run(
        [str(CI / script), *args],
        cwd=repo,
        capture_output=True,
        text=True,
        env={**os.environ, "MAIN_REF": "main", "DEV_REF": "dev", **(env or {})},
    )


@pytest.fixture
def repo(tmp_path):
    git(tmp_path, "init", "-q", "-b", "main")
    git(tmp_path, "config", "user.email", "test@example.com")
    git(tmp_path, "config", "user.name", "test")
    commit(tmp_path, "chore: initial commit")
    git(tmp_path, "checkout", "-q", "-b", "dev")
    return tmp_path


# --- next-version.sh --------------------------------------------------------


def next_version(repo, ref="dev"):
    result = run(repo, "next-version.sh", ref)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def test_first_release_is_v0_1_0(repo):
    commit(repo, "feat: first feature (#2)")
    assert next_version(repo) == "v0.1.0"


@pytest.mark.parametrize(
    "message, expected",
    [
        ("fix: handle empty body (#3)", "v1.4.3"),
        ("feat: add health action (#3)", "v1.5.0"),
        ("feat(api): scoped feature (#3)", "v1.5.0"),
        ("feat!: drop the v1 payload (#3)", "v2.0.0"),
        ("refactor(app)!: rename table (#3)", "v2.0.0"),
        ("feat: new table\n\nBREAKING CHANGE: old table is gone", "v2.0.0"),
        ("Update the readme (#3)", "v1.4.3"),
    ],
)
def test_bump_follows_the_biggest_change(repo, message, expected):
    git(repo, "tag", "v1.4.2")
    commit(repo, message)
    assert next_version(repo) == expected


def test_feature_wins_over_fixes(repo):
    git(repo, "tag", "v1.4.2")
    commit(repo, "fix: one (#3)")
    commit(repo, "feat: two (#4)")
    commit(repo, "fix: three (#5)")
    assert next_version(repo) == "v1.5.0"


def test_release_merge_commits_do_not_count(repo):
    commit(repo, "feat: first feature (#2)")
    main = release(repo)
    git(repo, "tag", "v0.1.0", main)
    commit(repo, "fix: a fix (#4)")
    main = release(repo)
    # The merge subject is not conventional; it must not change the bump.
    assert next_version(repo, main) == "v0.1.1"


def test_nothing_to_release_fails(repo):
    git(repo, "tag", "v1.0.0")
    result = run(repo, "next-version.sh", "dev")
    assert result.returncode != 0
    assert "Nothing to release" in result.stderr


# --- release-sha.sh ---------------------------------------------------------


def test_release_sha_is_dev_tip(repo):
    tip = commit(repo, "feat: thing (#2)")
    release(repo)
    result = run(repo, "release-sha.sh", "main")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == tip


def test_release_sha_refuses_a_direct_push(repo):
    git(repo, "checkout", "-q", "main")
    commit(repo, "fix: pushed straight to main")
    result = run(repo, "release-sha.sh", "main")
    assert result.returncode != 0
    assert "not a merge" in result.stderr


def test_release_sha_refuses_a_branch_other_than_dev(repo):
    git(repo, "checkout", "-q", "-b", "feature/x", "main")
    commit(repo, "feat: skipped dev (#9)")
    git(repo, "checkout", "-q", "main")
    git(repo, "merge", "-q", "--no-ff", "feature/x", "-m", "Merge feature/x")
    result = run(repo, "release-sha.sh", "main")
    assert result.returncode != 0
    assert "not from dev" in result.stderr


# --- check-prod.sh ----------------------------------------------------------


def check_prod(repo, sha, who="alice"):
    approvers = repo / "APPROVERS"
    approvers.write_text("# approvers\nalice\n")
    return run(repo, "check-prod.sh", "main", sha, who, str(approvers))


def test_prod_accepts_the_dev_build_a_release_merged(repo):
    tip = commit(repo, "feat: thing (#2)")
    release(repo)
    result = check_prod(repo, tip)
    assert result.returncode == 0, result.stderr


def test_prod_accepts_an_older_release_for_rollback(repo):
    old = commit(repo, "feat: thing (#2)")
    release(repo)
    commit(repo, "fix: later (#3)")
    release(repo)
    assert check_prod(repo, old).returncode == 0


def test_prod_refuses_a_dev_commit_that_was_never_released_as_the_tip(repo):
    middle = commit(repo, "feat: one (#2)")
    commit(repo, "feat: two (#3)")
    release(repo)
    result = check_prod(repo, middle)
    assert result.returncode != 0
    assert "never released" in result.stderr


def test_prod_refuses_someone_not_on_the_list(repo):
    tip = commit(repo, "feat: thing (#2)")
    release(repo)
    result = check_prod(repo, tip, who="mallory")
    assert result.returncode != 0
    assert "mallory is not in" in result.stderr


# --- release-notes.sh -------------------------------------------------------


def test_notes_list_every_pr_since_the_last_release(repo):
    commit(repo, "feat: old (#2)")
    git(repo, "tag", "v0.1.0", release(repo))
    commit(repo, "feat: add search (#4)")
    tip = commit(repo, "fix: empty query (#5)")
    main = release(repo)
    result = run(repo, "release-notes.sh", main)
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == [
        f"Build: {tip}",
        "",
        "## Changes since v0.1.0",
        "- fix: empty query (#5)",
        "- feat: add search (#4)",
    ]
