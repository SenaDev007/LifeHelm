// V2 — SMS Import : parsing automatique des SMS Mobile Money
import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';
import { parseMoMoSms } from '../services/sms-parser.js';

const router = Router();
router.use(authRequired);

// Importer un SMS (le client envoie le texte brut reçu)
router.post('/', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({
    rawSms: z.string().min(10),
    sender: z.string(),
    receivedAt: z.string().optional(),
  });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const { rawSms, sender, receivedAt } = parsed.data;
  const parsedTx = parseMoMoSms(rawSms, sender);

  const smsImport = await prisma.smsImport.create({
    data: {
      userId: req.userId!,
      rawSms,
      sender,
      receivedAt: receivedAt ? new Date(receivedAt) : new Date(),
      parsed: parsedTx as any,
    },
  });

  res.status(201).json({ smsImport, parsed: parsedTx });
});

// Lister les SMS importés
router.get('/', async (req: AuthedRequest, res: Response) => {
  const limit = Math.min(parseInt(String(req.query.limit || '50'), 10), 200);
  const imported = req.query.imported as string | undefined;

  const sms = await prisma.smsImport.findMany({
    where: {
      userId: req.userId,
      ...(imported === 'true' ? { imported: true } : imported === 'false' ? { imported: false } : {}),
    },
    orderBy: { receivedAt: 'desc' },
    take: limit,
  });
  res.json({ smsImports: sms });
});

// Convertir un SMS importé en transaction
router.post('/:id/convert', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ accountId: z.string() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const sms = await prisma.smsImport.findFirst({ where: { id: req.params.id, userId: req.userId } });
  if (!sms) return res.status(404).json({ error: 'NOT_FOUND' });
  if (sms.imported) return res.status(400).json({ error: 'ALREADY_IMPORTED' });

  const parsedTx = sms.parsed as any;
  if (!parsedTx || !parsedTx.amount) return res.status(400).json({ error: 'PARSE_FAILED' });

  // Vérifier le compte
  const account = await prisma.account.findFirst({ where: { id: parsed.data.accountId, userId: req.userId } });
  if (!account) return res.status(404).json({ error: 'ACCOUNT_NOT_FOUND' });

  // Créer la transaction
  const tx = await prisma.transaction.create({
    data: {
      userId: req.userId!,
      accountId: account.id,
      type: parsedTx.type || 'INCOME',
      amount: parsedTx.amount,
      category: parsedTx.category,
      label: parsedTx.label || `SMS ${sms.sender}`,
      note: `Importé depuis SMS du ${sms.receivedAt.toLocaleDateString('fr-FR')}`,
      date: sms.receivedAt,
    },
  });

  // Mettre à jour le solde
  const delta = tx.type === 'INCOME' ? tx.amount.toNumber() : tx.type === 'EXPENSE' ? -tx.amount.toNumber() : 0;
  if (delta !== 0) {
    await prisma.account.update({ where: { id: account.id }, data: { balance: { increment: delta } } });
  }

  // Marquer comme importé
  await prisma.smsImport.update({
    where: { id: sms.id },
    data: { imported: true, transactionId: tx.id },
  });

  res.status(201).json({ transaction: tx });
});

// Preview parsing (sans sauvegarder)
router.post('/preview', async (req: AuthedRequest, res: Response) => {
  const schema = z.object({ rawSms: z.string(), sender: z.string() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT' });

  const result = parseMoMoSms(parsed.data.rawSms, parsed.data.sender);
  res.json({ parsed: result });
});

export default router;
