import bcrypt from "bcrypt";
import { prisma } from "../src/index";
import { Decimal } from "@prisma/client/runtime/library";

async function main() {
  const email = "test@lifehelm.app";
  const existing = await prisma.user.findUnique({ where: { email } });
  if (existing) {
    // eslint-disable-next-line no-console
    console.log("Seed: user exists, skip");
    return;
  }

  const password = "Test1234!";
  const passwordHash = await bcrypt.hash(password, 12);

  const user = await prisma.user.create({
    data: {
      email,
      name: "Test User",
      passwordHash,
      plan: "PRO",
      currency: "XOF",
      language: "FR",
      uiMode: "STANDARD",
      timezone: "Africa/Porto-Novo",
    },
  });

  await prisma.account.createMany({
    data: [
      { userId: user.id, name: "Cash", type: "CASH", balance: new Decimal(0), isDefault: true },
      { userId: user.id, name: "Mobile Money", type: "MOBILE_MONEY_MTN", balance: new Decimal(0) },
    ],
  });

  await prisma.transaction.createMany({
    data: [
      {
        userId: user.id,
        accountId: (await prisma.account.findFirst({ where: { userId: user.id, isDefault: true } })).id,
        type: "INCOME",
        amount: new Decimal(50000),
        category: "salaire",
        date: new Date(),
      },
    ],
  });
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    await prisma.$disconnect();
    process.exit(1);
  });

