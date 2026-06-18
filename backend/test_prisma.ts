// Test direct Prisma
import 'dotenv/config';
import { prisma } from './src/db.js';

(async () => {
  try {
    console.log('DATABASE_URL:', process.env.DATABASE_URL?.substring(0, 60));
    const users = await prisma.user.count();
    console.log('✅ Users:', users);
  } catch (e) {
    console.error('❌ Erreur:', e.message);
  }
  await prisma.$disconnect();
})();
