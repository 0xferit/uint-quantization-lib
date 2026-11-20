import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { prepare } from "../scripts/commit-release.mjs";

function releaseFixture(context) {
  const directory = mkdtempSync(join(tmpdir(), "quantization-release-"));
  context.after(() => rmSync(directory, { recursive: true, force: true }));
  const repositoryUrl = join(directory, "remote.git");
  const cwd = join(directory, "checkout");
  const env = {
    ...process.env,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_AUTHOR_NAME: "Release Test",
    GIT_AUTHOR_EMAIL: "release@example.invalid",
    GIT_COMMITTER_NAME: "Release Test",
    GIT_COMMITTER_EMAIL: "release@example.invalid",
  };
  const git = (...args) =>
    execFileSync("git", args, { cwd, env, encoding: "utf8" }).trim();
  mkdirSync(join(cwd, "src"), { recursive: true });
  git("init", "--quiet", "--bare", repositoryUrl);
  git("init", "--quiet", "--initial-branch=main");
  const files = ["CHANGELOG.md", "README.md", "src/UintQuantizationLib.sol"];
  for (const file of files) writeFileSync(join(cwd, file), "original\n");
  git("add", "--", ...files);
  git("commit", "--quiet", "-m", "test: base");
  git("push", "--quiet", repositoryUrl, "HEAD:refs/heads/main");
  for (const file of files) writeFileSync(join(cwd, file), "prepared\n");
  const nextRelease = { version: "1.0.1", gitTag: "v1.0.1", notes: "Release notes" };
  return {
    git,
    repositoryUrl,
    release: () =>
      prepare({}, {
        cwd,
        env,
        options: { repositoryUrl },
        branch: { name: "main" },
        nextRelease,
      }),
  };
}

test("the remote branch and version tag point to the same prepared commit", async (context) => {
  const { git, release, repositoryUrl } = releaseFixture(context);
  await release();
  const commit = git("rev-parse", "HEAD");
  assert.equal(git("show", `${commit}:README.md`), "prepared");
  assert.equal(
    git("ls-remote", repositoryUrl, "refs/heads/main", "refs/tags/v1.0.1"),
    `${commit}\trefs/heads/main\n${commit}\trefs/tags/v1.0.1`,
  );
  assert.equal(git("tag", "--list", "v1.0.1"), "");
  git("tag", "v1.0.1", commit);
  git("push", "--quiet", "--tags", repositoryUrl);
});

test("a competing version tag leaves the remote branch untouched", async (context) => {
  const { git, release, repositoryUrl } = releaseFixture(context);
  git("push", "--quiet", repositoryUrl, "HEAD:refs/tags/v1.0.1");
  const refs = git("ls-remote", repositoryUrl, "refs/heads/main", "refs/tags/v1.0.1");
  await assert.rejects(async () => release());
  assert.equal(git("ls-remote", repositoryUrl, "refs/heads/main", "refs/tags/v1.0.1"), refs);
});
