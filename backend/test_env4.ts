import dotenv from 'dotenv';
console.log('CWD:', process.cwd());
const result = dotenv.config();
console.log('Erreur:', result.error);
console.log('Parsed:', result.parsed?.DATABASE_URL?.substring(0, 50));
