# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :git_ops,
  mix_project: MixSystemd.MixProject,
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/NarrativeApp/mix_systemd",
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"
