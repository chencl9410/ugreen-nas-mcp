#!/bin/sh
set -eu

case "${1:-}" in
  '') action=add ;;
  --remove) action=remove ;;
  -h|--help)
    printf '%s\n' '用法：./scripts/install.sh [--remove]'
    exit 0
    ;;
  *)
    printf '%s\n' '用法：./scripts/install.sh [--remove]' >&2
    exit 2
    ;;
esac
if [ "$#" -gt 1 ]; then
  printf '%s\n' '用法：./scripts/install.sh [--remove]' >&2
  exit 2
fi

command -v codex >/dev/null 2>&1 || {
  printf '%s\n' '未找到 Codex CLI，请确认 codex 命令已加入 PATH。' >&2
  exit 1
}

if [ "$action" = add ]; then
  project_dir=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
  node_bin=$(node -p 'Number(process.versions.node.split(".")[0]) >= 22 ? process.execPath : ""') || exit 1
  if [ -z "$node_bin" ] || [ ! -d "$project_dir/node_modules/@modelcontextprotocol/sdk" ]; then
    printf '%s\n' '请使用 Node.js 22 或更新版本，并在项目目录运行 npm ci --ignore-scripts。' >&2
    exit 1
  fi
  unc_bin=${UGREEN_UNC_BIN:-"$HOME/.local/bin/unc"}
  case "$unc_bin" in
    /*) ;;
    *)
      printf '%s\n' 'UGREEN_UNC_BIN 必须是 unc 的绝对路径。' >&2
      exit 1
      ;;
  esac
  if [ ! -x "$unc_bin" ]; then
    printf '%s\n' '未找到可执行的绿联 CLI。请先安装官方 unc，或设置 UGREEN_UNC_BIN。' >&2
    exit 1
  fi
  if codex mcp get ugreen-nas >/dev/null 2>&1; then
    printf '%s\n' '已存在 ugreen-nas 配置。若需迁移到新目录，请先检查并移除旧注册。' >&2
    exit 1
  fi
fi

config=${CODEX_HOME:-"$HOME/.codex"}/config.toml
if [ -f "$config" ]; then
  umask 077
  backup=$(mktemp "$config.ugreen-nas.XXXXXX")
  cat "$config" > "$backup"
  printf '配置备份：%s\n' "$backup"
fi

if [ "$action" = remove ]; then
  codex mcp remove ugreen-nas
else
  codex mcp add ugreen-nas --env "UGREEN_UNC_BIN=$unc_bin" -- "$node_bin" "$project_dir/server.mjs"
  codex mcp get ugreen-nas
fi
