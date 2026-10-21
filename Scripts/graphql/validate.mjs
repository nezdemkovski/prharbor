// Validates every GraphQL document PR Harbor sends against GitHub's public schema and
// writes the selected fields with their nullability, so a newly selected nullable field
// shows up in review. Usage: node validate.mjs <documents-dir> <report-file>
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { buildSchema, parse, validate, visit, TypeInfo, visitWithTypeInfo, isNonNullType } from 'graphql';

const [directory, report] = process.argv.slice(2);
const schema = buildSchema(readFileSync(new URL('./github-schema.graphqls', import.meta.url), 'utf8'));
const fields = new Map();
let failed = false;

const files = readdirSync(directory).filter((name) => name.endsWith('.graphql')).sort();
if (files.length === 0) { console.error(`No documents in ${directory}`); process.exit(1); }
for (const file of files) {
  const document = parse(readFileSync(`${directory}/${file}`, 'utf8'));
  const errors = validate(schema, document);
  for (const error of errors) { failed = true; console.error(`${file}: ${error.message}`); }
  if (errors.length === 0) console.log(`${file}: valid`);
  const info = new TypeInfo(schema);
  visit(document, visitWithTypeInfo(info, {
    Field(node) {
      const type = info.getType(), parent = info.getParentType();
      if (!type || node.name.value === '__typename') return;
      fields.set(`${parent.name}.${node.name.value}`, `${isNonNullType(type) ? 'non-null' : 'nullable'} ${type}`);
    },
  }));
}
writeFileSync(report, [...fields].sort().map(([field, type]) => `${field}: ${type}`).join('\n') + '\n');
process.exit(failed ? 1 : 0);
