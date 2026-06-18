import dotenv from 'dotenv';
const result = dotenv.config({ path: './.env' });
console.log('Erreur:', result.error);
console.log('Parsed DATABASE_URL:', result.parsed?.DATABASE_URL?.substring(0, 50));
