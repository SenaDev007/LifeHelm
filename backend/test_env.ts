import dotenv from 'dotenv';
dotenv.config();
console.log('CWD:', process.cwd());
console.log('DB URL start:', process.env.DATABASE_URL?.substring(0, 80));
