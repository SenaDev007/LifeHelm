import 'dotenv/config';
console.log('At runtime, DATABASE_URL =', process.env.DATABASE_URL?.substring(0, 80));
import { prisma } from './src/db.js';
console.log('Prisma chargé, count:');
prisma.user.count().then(c => {
  console.log('✅', c);
  process.exit(0);
}).catch(e => {
  console.error('❌', e.message.substring(0, 200));
  process.exit(1);
});
