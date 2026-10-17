#!/usr/bin/env bash
# Install what the Bitbucket steps need on top of their image: OpenTofu
# (pinned, checksum verified), jq, zip, unzip, git. GitHub uses
# opentofu/setup-opentofu instead. At work, images and downloads should come
# through the JFrog proxy (set TOFU_BASE_URL to its GitHub remote).
set -euo pipefail
TOFU_VERSION="${TOFU_VERSION:-1.12.0}"
TOFU_BASE_URL="${TOFU_BASE_URL:-https://github.com/opentofu/opentofu/releases/download}"

if command -v apt-get >/dev/null; then
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    ca-certificates curl jq zip unzip git make >/dev/null
elif command -v dnf >/dev/null; then
  dnf install -y -q jq zip unzip git make tar gzip >/dev/null
elif command -v yum >/dev/null; then
  yum install -y -q jq zip unzip git make tar gzip >/dev/null
fi

if ! tofu version 2>/dev/null | grep -q "v$TOFU_VERSION"; then
  case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64 | arm64) arch=arm64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac
  tmp="$(mktemp -d)"
  zip="tofu_${TOFU_VERSION}_linux_${arch}.zip"
  curl -fsSL -o "$tmp/$zip" "$TOFU_BASE_URL/v$TOFU_VERSION/$zip"
  curl -fsSL -o "$tmp/SHA256SUMS" "$TOFU_BASE_URL/v$TOFU_VERSION/tofu_${TOFU_VERSION}_SHA256SUMS"
  (cd "$tmp" && grep " $zip\$" SHA256SUMS | sha256sum -c -)
  unzip -q -o "$tmp/$zip" tofu -d /usr/local/bin
  rm -rf "$tmp"
fi
tofu version | head -1
