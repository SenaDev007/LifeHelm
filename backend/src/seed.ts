import dotenv from 'dotenv';
import path from 'node:path';
dotenv.config({ path: path.resolve(process.cwd(), '.env'), override: true });

import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding LifeHelm database...');

  // Demo user
  const passwordHash = await bcrypt.hash('lifehelm123', 12);
  const user = await prisma.user.upsert({
    where: { email: 'demo@lifehelm.app' },
    update: {},
    create: {
      email: 'demo@lifehelm.app',
      passwordHash,
      firstName: 'Kofi',
      lastName: 'Demo',
      phone: '+22901000000',
      plan: 'PRO',
      language: 'FR',
      appMode: 'STANDARD',
      currency: 'XOF',
      onboarded: true,
      settings: { create: {} },
    },
  });

  console.log(`  ✓ User: ${user.email}`);

  // Accounts
  const cashAccount = await prisma.account.create({
    data: { userId: user.id, name: 'Cash', type: 'CASH', balance: 25000, color: '#10B981' },
  });
  const momoAccount = await prisma.account.create({
    data: { userId: user.id, name: 'MTN MoMo', type: 'MOBILE_MONEY_MTN', balance: 78000, color: '#FFCC00' },
  });
  const bankAccount = await prisma.account.create({
    data: { userId: user.id, name: 'Banque BOA', type: 'BANK', balance: 320000, color: '#3B82F6' },
  });
  console.log('  ✓ Accounts: Cash, MTN MoMo, BOA');

  // Transactions du mois
  const now = new Date();
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  const categories = ['Alimentation', 'Transport', 'Santé', 'École', 'Loyer', 'Transfert famille', 'Communication', 'Loisirs'];
  const labels: Record<string, string[]> = {
    Alimentation: ['Marché Dantokpa', 'Riz et tomate', 'Pain et café'],
    Transport: ['Taxi-moto', 'Essence', 'Bus'],
    Santé: ['Pharmacie', 'Consultation'],
    École: ['Frais scolarité', 'Cahiers'],
    Loyer: ['Loyer mensuel'],
    'Transfert famille': ['Envoi maman', 'Aide frère'],
    Communication: ['Crédit MTN', 'Forfait internet'],
    Loisirs: ['Cinéma', 'Sortie restaurant'],
  };

  const transactions = [];
  for (let i = 0; i < 25; i++) {
    const day = Math.floor(Math.random() * 28) + 1;
    const date = new Date(now.getFullYear(), now.getMonth(), day);
    const isIncome = Math.random() < 0.3;
    const category = isIncome ? 'Revenu' : categories[Math.floor(Math.random() * categories.length)];
    const label = isIncome
      ? ['Salaire freelance', 'Vente projet', 'Tontine reçue'][Math.floor(Math.random() * 3)]
      : labels[category][Math.floor(Math.random() * labels[category].length)];
    const amount = isIncome
      ? Math.round((Math.random() * 100 + 20) * 1000)
      : Math.round((Math.random() * 20 + 1) * 500);

    transactions.push({
      userId: user.id,
      accountId: [cashAccount.id, momoAccount.id, bankAccount.id][Math.floor(Math.random() * 3)],
      type: isIncome ? 'INCOME' : 'EXPENSE',
      amount,
      category,
      label,
      date,
    });
  }
  await prisma.transaction.createMany({ data: transactions });
  console.log(`  ✓ ${transactions.length} transactions créées`);

  // Savings goal
  await prisma.savingsGoal.create({
    data: {
      userId: user.id,
      name: 'Machine à coudre',
      description: 'Pour ouvrir mon atelier de couture',
      targetAmount: 250000,
      currentAmount: 95000,
      deadline: new Date(now.getFullYear() + 1, now.getMonth(), 1),
    },
  });
  await prisma.savingsGoal.create({
    data: {
      userId: user.id,
      name: 'Fonds urgence',
      targetAmount: 500000,
      currentAmount: 230000,
    },
  });
  console.log('  ✓ 2 objectifs d\'épargne');

  // Tontine
  const tontine = await prisma.tontine.create({
    data: {
      userId: user.id,
      name: 'Tontine du marché',
      contributionAmount: 10000,
      frequency: 'MONTHLY',
      startDate: new Date(now.getFullYear(), now.getMonth() - 3, 1),
      myRank: 3,
      totalMembers: 5,
      members: {
        create: [
          { name: 'Awa', rank: 1, paid: true, paidAt: new Date(now.getFullYear(), now.getMonth() - 2, 5), received: true, receivedAt: new Date(now.getFullYear(), now.getMonth() - 2, 5) },
          { name: 'Marius', rank: 2, paid: true, paidAt: new Date(now.getFullYear(), now.getMonth() - 1, 5), received: true, receivedAt: new Date(now.getFullYear(), now.getMonth() - 1, 5) },
          { name: 'Kofi (moi)', rank: 3, paid: true, paidAt: new Date(now.getFullYear(), now.getMonth(), 5) },
          { name: 'Bénédicte', rank: 4, paid: false },
          { name: 'Yaovi', rank: 5, paid: false },
        ],
      },
    },
    include: { members: true },
  });
  console.log(`  ✓ Tontine "${tontine.name}" avec ${tontine.members.length} membres`);

  // Debt
  await prisma.debt.create({
    data: {
      userId: user.id,
      direction: 'OWING',
      personName: 'Oncle Koffi',
      amount: 50000,
      dueDate: new Date(now.getFullYear(), now.getMonth() + 1, 15),
      note: 'Avance pour le stock',
    },
  });
  await prisma.debt.create({
    data: {
      userId: user.id,
      direction: 'OWED',
      personName: 'Cliente Awa',
      amount: 15000,
      dueDate: new Date(now.getFullYear(), now.getMonth(), now.getDate() + 7),
    },
  });

  // Bill
  await prisma.bill.create({
    data: {
      userId: user.id,
      name: 'SBEE Électricité',
      amount: 18000,
      category: 'Utilities',
      recurrence: 'MONTHLY',
      dueDay: 15,
      nextDueDate: new Date(now.getFullYear(), now.getMonth(), 15),
    },
  });
  await prisma.bill.create({
    data: {
      userId: user.id,
      name: 'SONEB Eau',
      amount: 8000,
      category: 'Utilities',
      recurrence: 'MONTHLY',
      dueDay: 20,
      nextDueDate: new Date(now.getFullYear(), now.getMonth(), 20),
    },
  });
  console.log('  ✓ 2 factures récurrentes');

  // Habits
  const meditation = await prisma.habit.create({
    data: { userId: user.id, name: 'Méditation 10min', type: 'BINARY', frequency: 'DAILY', color: '#8B5CF6', reminderHour: 6, reminderMin: 30 },
  });
  const water = await prisma.habit.create({
    data: { userId: user.id, name: 'Boire 2L d\'eau', type: 'NUMERIC', frequency: 'DAILY', targetValue: 2, unit: 'L', color: '#06B6D4' },
  });
  const reading = await prisma.habit.create({
    data: { userId: user.id, name: 'Lire 20min', type: 'BINARY', frequency: 'DAILY', color: '#F59E0B', reminderHour: 20, reminderMin: 0 },
  });
  console.log('  ✓ 3 habitudes');

  // Habit logs (7 derniers jours)
  const habitLogs = [];
  for (let i = 0; i < 7; i++) {
    const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
    const dateOnly = new Date(date.toISOString().slice(0, 10));
    habitLogs.push({ habitId: meditation.id, userId: user.id, date: dateOnly, completed: Math.random() > 0.3 });
    habitLogs.push({ habitId: water.id, userId: user.id, date: dateOnly, value: Math.round(Math.random() * 20) / 10, completed: true });
    habitLogs.push({ habitId: reading.id, userId: user.id, date: dateOnly, completed: Math.random() > 0.5 });
  }
  await prisma.habitLog.createMany({ data: habitLogs });
  console.log(`  ✓ ${habitLogs.length} habit logs`);

  // Sleep logs (7 derniers jours)
  const sleepLogs = [];
  for (let i = 0; i < 7; i++) {
    const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
    const dateOnly = new Date(date.toISOString().slice(0, 10));
    const bedtime = new Date(date);
    bedtime.setHours(22 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
    const wakeTime = new Date(date);
    wakeTime.setDate(wakeTime.getDate() + 1);
    wakeTime.setHours(6 + Math.floor(Math.random() * 2), Math.floor(Math.random() * 60));
    const durationMin = Math.round((wakeTime.getTime() - bedtime.getTime()) / 60000);
    sleepLogs.push({
      userId: user.id,
      date: dateOnly,
      bedtime, wakeTime,
      durationMin,
      quality: Math.floor(Math.random() * 3) + 3,
    });
  }
  await prisma.sleepLog.createMany({ data: sleepLogs });
  console.log(`  ✓ ${sleepLogs.length} sleep logs`);

  // Mood logs
  const moodLogs = [];
  const moods = ['VERY_BAD', 'BAD', 'NEUTRAL', 'GOOD', 'VERY_GOOD'];
  for (let i = 0; i < 7; i++) {
    const date = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
    moodLogs.push({
      userId: user.id,
      date: new Date(date.toISOString().slice(0, 10)),
      mood: moods[Math.floor(Math.random() * 3) + 1] as any,
      energy: Math.floor(Math.random() * 5) + 4,
      emotions: [],
    });
  }
  await prisma.moodLog.createMany({ data: moodLogs });
  console.log(`  ✓ ${moodLogs.length} mood logs`);

  // Workouts
  const workoutTypes = ['Course', 'Marche', 'Football', 'Yoga', 'Musculation'];
  for (let i = 0; i < 3; i++) {
    const date = new Date(now.getTime() - i * 2 * 24 * 60 * 60 * 1000);
    await prisma.workoutLog.create({
      data: {
        userId: user.id,
        date: new Date(date.toISOString().slice(0, 10)),
        type: workoutTypes[i],
        durationMin: 30 + Math.floor(Math.random() * 60),
        intensity: Math.floor(Math.random() * 3) + 2,
      },
    });
  }
  console.log('  ✓ 3 workout logs');

  // Life goals
  await prisma.lifeGoal.create({
    data: {
      userId: user.id,
      domain: 'FINANCE',
      title: 'Épargner 500.000 FCFA',
      description: 'Constituer un fonds d\'urgence de 6 mois de dépenses',
      type: 'NUMERIC',
      priority: 'HIGH',
      targetValue: 500000,
      currentValue: 230000,
      unit: 'FCFA',
      deadline: new Date(now.getFullYear() + 1, now.getMonth(), 1),
    },
  });
  await prisma.lifeGoal.create({
    data: {
      userId: user.id,
      domain: 'CAREER',
      title: 'Lancer mon activité de couture',
      description: 'Ouvrir un atelier avec 3 machines à coudre',
      type: 'MILESTONE',
      priority: 'HIGH',
      deadline: new Date(now.getFullYear() + 1, now.getMonth(), 1),
    },
  });
  await prisma.lifeGoal.create({
    data: {
      userId: user.id,
      domain: 'HEALTH',
      title: 'Dormir 7h+ par nuit',
      type: 'BINARY',
      priority: 'MEDIUM',
    },
  });
  console.log('  ✓ 3 objectifs de vie');

  // Boutique log (mode accessible)
  await prisma.dailyBoutiqueLog.create({
    data: {
      userId: user.id,
      date: new Date(now.toISOString().slice(0, 10)),
      openingCapital: 10000,
      restockCost: 5000,
      totalSales: 25000,
      netProfit: 20000,
    },
  });
  console.log('  ✓ 1 boutique log (mode accessible)');

  console.log('\n✅ Seed terminé. Login: demo@lifehelm.app / lifehelm123');
}

main()
  .catch((e) => {
    console.error('❌ Erreur seed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
