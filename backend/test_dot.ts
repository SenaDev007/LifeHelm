console.log('AVANT:', process.env.DATABASE_URL);
const dotenv = require('dotenv');
console.log('dotenv:', typeof dotenv);
const r = dotenv.config();
console.log('Parsed:', r.parsed?.DATABASE_URL?.substring(0, 50));
console.log('APRES:', process.env.DATABASE_URL?.substring(0, 50));
