import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, renameSync, rmSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { uncEnvironment } from '../lib/unc.mjs';

const [command, cachePath, ...extra] = process.argv.slice(2);
const commands = ['build', 'store', 'import-cache', 'import-legacy-keychain', 'check'];
if (!command || command === '--help' || !commands.includes(command) ||
    extra.length || (cachePath !== undefined && command !== 'import-cache')) {
  console.error('Usage: npm run keychain -- build|store|import-cache [path]|import-legacy-keychain|check');
  process.exit(command === '--help' ? 0 : 1);
}
if (process.platform !== 'darwin') {
  console.error('The Keychain launcher requires macOS.');
  process.exit(1);
}

const launcher = fileURLToPath(new URL('../build/unc-keychain', import.meta.url));
if (command === 'build') {
  const source = fileURLToPath(new URL('../native/unc-keychain.m', import.meta.url));
  const launcherStat = statSync(launcher, { throwIfNoEntry: false });
  if (launcherStat?.mtimeMs >= statSync(source).mtimeMs) {
    execFileSync('/usr/bin/codesign', ['--verify', '--strict', launcher]);
    console.log('Keychain launcher is up to date.');
    process.exit(0);
  }
  const buildDirectory = dirname(launcher);
  mkdirSync(buildDirectory, { recursive: true, mode: 0o700 });
  const temporaryDirectory = mkdtempSync(join(buildDirectory, '.compile-'));
  try {
    const binary = join(temporaryDirectory, 'unc-keychain');
    execFileSync('/usr/bin/xcrun', ['--sdk', 'macosx', 'clang', '-Wall', '-Wextra', '-Werror',
      '-fobjc-arc', '-framework', 'Foundation', '-framework', 'Security', '-o', binary, source],
    { stdio: 'inherit' });
    execFileSync('/usr/bin/codesign', ['--force', '--sign', '-',
      '--identifier', 'io.github.ugreen-nas-mcp-macos.launcher', binary], { stdio: 'inherit' });
    execFileSync('/usr/bin/codesign', ['--verify', '--strict', binary]);
    renameSync(binary, launcher);
    console.log('Keychain launcher built.');
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
} else {
  const args = [`--${command}`];
  if (cachePath !== undefined) args.push(resolve(cachePath));
  const result = spawnSync(launcher, args, { stdio: 'inherit', env: uncEnvironment() });
  if (result.error) {
    console.error('无法启动钥匙串程序，请先运行 npm run keychain -- build。');
  }
  process.exitCode = result.status ?? 1;
}
