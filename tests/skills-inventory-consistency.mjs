#!/usr/bin/env node
// Verifies that the tracked skill store and the skill lockfile describe the
// same inventory, comparing skill *names* rather than counts.
//
// Usage: node tests/skills-inventory-consistency.mjs [repo-root]

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(
  process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), '..'),
);
const skillsDir = join(repoRoot, 'config', 'agents', 'skills');
const lockPath = join(repoRoot, 'config', 'agents', '.skill-lock.json');

const fail = (message) => {
  console.log(`FAIL: ${message}`);
  process.exit(1);
};

let lock;
try {
  lock = JSON.parse(readFileSync(lockPath, 'utf8'));
} catch (error) {
  fail(`cannot read ${lockPath}: ${error.message}`);
}

if (!lock || typeof lock.skills !== 'object' || lock.skills === null || Array.isArray(lock.skills)) {
  fail(`${lockPath} has no "skills" object`);
}

let entries;
try {
  entries = readdirSync(skillsDir, { withFileTypes: true });
} catch (error) {
  fail(`cannot read ${skillsDir}: ${error.message}`);
}

const lockedNames = Object.keys(lock.skills);
const trackedNames = entries
  .filter((entry) => entry.isDirectory() || entry.isSymbolicLink())
  .filter((entry) => statSync(join(skillsDir, entry.name), { throwIfNoEntry: false })?.isDirectory())
  .map((entry) => entry.name);

const locked = new Set(lockedNames);
const tracked = new Set(trackedNames);

const missingOnDisk = lockedNames.filter((name) => !tracked.has(name)).sort();
const missingInLock = trackedNames.filter((name) => !locked.has(name)).sort();

const drift = [];

for (const name of missingOnDisk) {
  drift.push(`locked but no matching skill directory: ${name}`);
}

for (const name of missingInLock) {
  drift.push(`skill directory without a lock entry: ${name}`);
}

if (drift.length > 0) {
  console.log('Skill inventory drift detected:');
  for (const line of drift) {
    console.log(`  - ${line}`);
  }
  console.log(
    `Tracked skill directories: ${tracked.size}, lock entries: ${locked.size}`,
  );
  if (tracked.size === locked.size) {
    console.log('Equal counts do not imply matching inventories.');
  }
  fail('skill inventory is inconsistent; reconcile skills/ with .skill-lock.json');
}

console.log(
  `PASS: skills inventory consistent (${tracked.size} tracked skills, ${locked.size} lock entries)`,
);
