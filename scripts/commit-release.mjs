import { execFileSync } from "node:child_process";

export function prepare(_, { branch, cwd, env, nextRelease, options }) {
  const gitOptions = { cwd, env, encoding: "utf8" };
  const tagSigning = execFileSync(
    "git",
    ["config", "--type=bool", "--default=false", "--get", "tag.gpgSign"],
    gitOptions,
  ).trim();
  if (tagSigning === "true") {
    throw new Error("Atomic release preparation requires lightweight version tags.");
  }

  const { version, gitTag, notes } = nextRelease;
  const message = `chore(release): ${version} [skip ci]\n\n${notes}`;
  execFileSync(
    "git",
    ["commit", "--only", "-m", message, "--", "CHANGELOG.md", "src/UintQuantizationLib.sol"],
    gitOptions,
  );

  const tagRef = `refs/tags/${gitTag}`;
  execFileSync(
    "git",
    [
      "--config-env=remote.release-transaction.url=RELEASE_REPOSITORY_URL",
      "push",
      "--atomic",
      `--force-with-lease=${tagRef}:`,
      "release-transaction",
      `HEAD:refs/heads/${branch.name}`,
      `HEAD:${tagRef}`,
    ],
    { ...gitOptions, env: { ...env, RELEASE_REPOSITORY_URL: options.repositoryUrl } },
  );
}
