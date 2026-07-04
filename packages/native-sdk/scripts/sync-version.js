#!/usr/bin/env node

import { readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(__dirname, '..');
const repoRoot = join(projectRoot, '..', '..');

const packageJson = JSON.parse(readFileSync(join(projectRoot, 'package.json'), 'utf-8'));
const version = packageJson.version;

console.log(`Syncing version ${version} to tools/native-sdk/main.zig...`);

const mainZigPath = join(repoRoot, 'tools', 'native-sdk', 'main.zig');
let mainZig = readFileSync(mainZigPath, 'utf-8');

const versionPattern = /^const version = "[^"]*";/m;
const match = mainZig.match(versionPattern);

if (!match) {
  console.error('  Could not find `const version = "...";` in tools/native-sdk/main.zig');
  process.exit(1);
}

const newVersionLine = `const version = "${version}";`;

if (match[0] !== newVersionLine) {
  mainZig = mainZig.replace(versionPattern, newVersionLine);
  writeFileSync(mainZigPath, mainZig);
  console.log(`  Updated tools/native-sdk/main.zig: ${match[0]} -> ${newVersionLine}`);
} else {
  console.log(`  tools/native-sdk/main.zig already up to date`);
}

console.log('Version sync complete.');
