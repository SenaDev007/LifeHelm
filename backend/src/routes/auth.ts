import { Router, type Request, type Response, type NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { prisma } from '../db.js';
import { config } from '../config.js';
import { generateTokens, setAuthCookies, hashToken } from '../utils/auth.js';

const router = Router();

const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  firstName: z.string().min(1).max(80),
  lastName: z.string().max(80).optional(),
  phone: z.string().max(30).optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

// ---------- SIGNUP ----------
router.post('/signup', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = signupSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'INVALID_INPUT', details: parsed.error.issues });
    }
    const { email, password, firstName, lastName, phone } = parsed.data;

    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
      return res.status(409).json({ error: 'EMAIL_TAKEN' });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const user = await prisma.user.create({
      data: {
        email,
        passwordHash,
        firstName,
        lastName,
        phone,
        settings: { create: {} },
      },
      select: { id: true, email: true, firstName: true, lastName: true, plan: true, language: true, appMode: true },
    });

    const { accessToken, refreshToken } = generateTokens(user.id);
    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        token: hashToken(refreshToken),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });

    setAuthCookies(res, accessToken, refreshToken);
    return res.status(201).json({ user, accessToken });
  } catch (e) {
    next(e);
  }
});

// ---------- LOGIN ----------
router.post('/login', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const parsed = loginSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'INVALID_INPUT' });
    }
    const { email, password } = parsed.data;

    const user = await prisma.user.findUnique({ where: { email } });
    if (!user) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) return res.status(401).json({ error: 'INVALID_CREDENTIALS' });

    const { accessToken, refreshToken } = generateTokens(user.id);
    await prisma.refreshToken.create({
      data: {
        userId: user.id,
        token: hashToken(refreshToken),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    await prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });

    setAuthCookies(res, accessToken, refreshToken);

    return res.json({
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        plan: user.plan,
        language: user.language,
        appMode: user.appMode,
        onboarded: user.onboarded,
        accessibleOnboarded: user.accessibleOnboarded,
      },
      accessToken,
    });
  } catch (e) {
    next(e);
  }
});

// ---------- REFRESH ----------
router.post('/refresh', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const refreshToken = req.cookies?.refresh_token;
    if (!refreshToken) return res.status(401).json({ error: 'NO_REFRESH_TOKEN' });

    let payload: { sub: string };
    try {
      payload = jwt.verify(refreshToken, config.jwt.refreshSecret) as { sub: string };
    } catch {
      return res.status(401).json({ error: 'INVALID_REFRESH_TOKEN' });
    }

    const stored = await prisma.refreshToken.findFirst({
      where: { token: hashToken(refreshToken), userId: payload.sub, revoked: false },
    });
    if (!stored) return res.status(401).json({ error: 'INVALID_REFRESH_TOKEN' });

    // Rotation
    await prisma.refreshToken.update({ where: { id: stored.id }, data: { revoked: true } });

    const tokens = generateTokens(payload.sub);
    await prisma.refreshToken.create({
      data: {
        userId: payload.sub,
        token: hashToken(tokens.refreshToken),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    setAuthCookies(res, tokens.accessToken, tokens.refreshToken);
    return res.json({ accessToken: tokens.accessToken });
  } catch (e) {
    next(e);
  }
});

// ---------- LOGOUT ----------
router.post('/logout', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const refreshToken = req.cookies?.refresh_token;
    if (refreshToken) {
      await prisma.refreshToken.updateMany({
        where: { token: hashToken(refreshToken) },
        data: { revoked: true },
      });
    }
    res.clearCookie('access_token');
    res.clearCookie('refresh_token');
    return res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

// ---------- ME ----------
router.get('/me', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'UNAUTHORIZED' });
    }
    const token = authHeader.slice(7);
    let payload: { sub: string };
    try {
      payload = jwt.verify(token, config.jwt.accessSecret) as { sub: string };
    } catch {
      return res.status(401).json({ error: 'INVALID_TOKEN' });
    }

    const user = await prisma.user.findUnique({
      where: { id: payload.sub },
      select: {
        id: true, email: true, firstName: true, lastName: true, phone: true,
        plan: true, language: true, appMode: true, currency: true,
        onboarded: true, accessibleOnboarded: true,
        avatarUrl: true, createdAt: true,
      },
    });
    if (!user) return res.status(404).json({ error: 'USER_NOT_FOUND' });

    return res.json({ user });
  } catch (e) {
    next(e);
  }
});

export default router;
