import { Router, type Response } from 'express';
import { z } from 'zod';
import { prisma } from '../db.js';
import { authRequired, type AuthedRequest } from '../middleware/auth.js';

const router = Router();
router.use(authRequired);

const contactSchema = z.object({
  firstName: z.string().min(1).max(80),
  lastName: z.string().max(80).nullable().optional(),
  phone: z.string().max(30).nullable().optional(),
  email: z.string().email().nullable().optional().or(z.literal('')),
  city: z.string().max(100).nullable().optional(),
  circle: z.enum(['FAMILY_CLOSE', 'FAMILY_EXTENDED', 'FRIEND', 'COLLEAGUE', 'MENTOR', 'NETWORK']).optional(),
  birthday: z.string().nullable().optional(),
  lastContactAt: z.string().nullable().optional(),
  note: z.string().max(2000).nullable().optional(),
});

router.get('/', async (req: AuthedRequest, res: Response) => {
  const contacts = await prisma.contact.findMany({ where: { userId: req.userId }, orderBy: [{ circle: 'asc' }, { firstName: 'asc' }] });
  const now = new Date();
  const items = contacts.map((contact) => {
    let daysUntilBirthday: number | null = null;
    if (contact.birthday) {
      const birthday = contact.birthday;
      let next = new Date(now.getFullYear(), birthday.getMonth(), birthday.getDate());
      if (next < new Date(now.getFullYear(), now.getMonth(), now.getDate())) next = new Date(now.getFullYear() + 1, birthday.getMonth(), birthday.getDate());
      daysUntilBirthday = Math.round((next.getTime() - new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()) / 86400000);
    }
    return { ...contact, daysUntilBirthday };
  });
  res.json({ contacts: items });
});

router.post('/', async (req: AuthedRequest, res: Response) => {
  const parsed = contactSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const data = parsed.data;
  const contact = await prisma.contact.create({
    data: {
      userId: req.userId!, firstName: data.firstName, lastName: data.lastName, phone: data.phone,
      email: data.email || null, city: data.city, circle: data.circle, note: data.note,
      birthday: data.birthday ? new Date(data.birthday) : null,
      lastContactAt: data.lastContactAt ? new Date(data.lastContactAt) : null,
    },
  });
  res.status(201).json({ contact });
});

router.patch('/:id', async (req: AuthedRequest, res: Response) => {
  const parsed = contactSchema.partial().safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
  const { birthday, lastContactAt, ...rest } = parsed.data;
  const result = await prisma.contact.updateMany({
    where: { id: req.params.id, userId: req.userId },
    data: {
      ...rest,
      ...(birthday !== undefined ? { birthday: birthday ? new Date(birthday) : null } : {}),
      ...(lastContactAt !== undefined ? { lastContactAt: lastContactAt ? new Date(lastContactAt) : null } : {}),
    },
  });
  if (!result.count) return res.status(404).json({ error: 'NOT_FOUND' });
  const contact = await prisma.contact.findFirst({ where: { id: req.params.id, userId: req.userId } });
  res.json({ contact });
});

router.delete('/:id', async (req: AuthedRequest, res: Response) => {
  const result = await prisma.contact.deleteMany({ where: { id: req.params.id, userId: req.userId } });
  if (!result.count) return res.status(404).json({ error: 'NOT_FOUND' });
  res.json({ ok: true });
});

export default router;
