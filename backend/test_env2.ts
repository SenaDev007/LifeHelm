import * as fs from 'fs';
const content = fs.readFileSync('.env', 'utf8');
console.log('Contenu .env brut:');
console.log(content);
console.log('---');
const lines = content.split('\n');
for (const line of lines) {
  if (line.startsWith('DATABASE_URL')) {
    const m = line.match(/DATABASE_URL\s*=\s*"?([^"]+)"?/);
    if (m) console.log('Parsed:', m[1].substring(0, 50));
  }
}
