// plan.mjs — `selvedge plan`, run by selvedge/bin/selvedge.
//
//   selvedge plan --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
//
// --validate runs the static lint (plan-validate.mjs) against the run folder's criteria.json (the
// file beside the plan unless --criteria names another) and selvedge.json (the working tree, or the
// committed <ref>:selvedge.json with --base, exactly as `env check --base`). Every problem is one
// stderr line `plan_invalid: <criterion id | (plan)>: <code>: <detail>`; any problem exits 2.
//
// Exit codes (00-plan D7): 0 ok, 1 an operation failed, 2 usage error, BLOCKED or a named reason,
// 3 NOT_VERIFIABLE. Every reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { EnvError, UsageError, loadConfig, parseCliArgs } from './env-config.mjs';
import { readCriteriaFile } from './criteria.mjs';
import { PLAN_SCOPE, problemLine, validatePlan } from './plan-validate.mjs';

const USAGE = `Usage: selvedge plan <command>

Commands:
  --validate <plan.json> [--criteria <criteria.json>] [--base <ref>]
                           lint a plan: the PASS rule (a value read after the last action),
                           negative baselines, interpretation/polarity/assumptions, criterion
                           coverage, criteria_sha256, and every step's type, fields, locator,
                           content and goto origin. Lists every problem, one stderr line each.
                           criteria.json defaults to the file beside the plan.

Exit codes: 0 ok, 1 an operation failed, 2 usage error, BLOCKED or a named reason, 3 NOT_VERIFIABLE.`;

function err(line) {
  process.stderr.write(`selvedge plan: ${line}\n`);
}

// The plan file's JSON, or a plan_invalid problem list when it cannot be read or parsed.
function readPlan(file) {
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (e) {
    return { problems: [{ id: PLAN_SCOPE, code: 'plan_schema_violation', detail: `cannot read ${file}: ${e && e.code ? e.code : e && e.message}` }] };
  }
  try {
    return { plan: JSON.parse(raw) };
  } catch (e) {
    return { problems: [{ id: PLAN_SCOPE, code: 'plan_schema_violation', detail: `${file} is not valid JSON: ${e && e.message}` }] };
  }
}

function cmdValidate(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['validate', 'criteria', 'base'] });
  if (positional.length) throw new UsageError(`unexpected argument: ${positional[0]}`);
  const file = flags.validate;
  const criteriaFile = flags.criteria || path.join(path.dirname(file), 'criteria.json');
  const criteria = readCriteriaFile(criteriaFile);
  const { config, source } = loadConfig({ base: flags.base });
  const read = readPlan(file);
  const problems = read.problems || validatePlan(read.plan, { criteria, config });
  if (problems.length) {
    for (const p of problems) process.stderr.write(`${problemLine(p)}\n`);
    err(`${problems.length} problem(s) in ${file} (criteria: ${criteriaFile}; config source: ${source})`);
    return 2;
  }
  process.stdout.write(`plan valid: ${file}\n`);
  err(`criteria: ${criteriaFile}; config source: ${source}`);
  return 0;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  try {
    if (argv.length === 0) {
      process.stderr.write(`${USAGE}\n`);
      return 2;
    }
    if (['help', '-h', '--help'].includes(argv[0])) {
      process.stdout.write(`${USAGE}\n`);
      return 0;
    }
    if (argv.some((a) => a === '--validate' || a.startsWith('--validate='))) return cmdValidate(argv);
    throw new UsageError(`unknown plan command: ${argv.join(' ')}`);
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) {
      if (e.blocked) {
        process.stdout.write(`BLOCKED ${e.reason}\n`);
      }
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
process.exitCode = await main(process.argv.slice(2));
