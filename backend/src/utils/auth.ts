import jwt, { type Secret, type SignOptions } from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import type { Response } from 'express';
import { config } from '../config.js';

export function generateTokens(userId: string) {
  const accessSecret: Secret = config.jwt.accessSecret;
  const refreshSecret: Secret = config.jwt.refreshSecret;
  const accessToken = jwt.sign({ sub: userId }, accessSecret, {
    expiresIn: config.jwt.accessExpires,
  } as SignOptions);
  const refreshToken = jwt.sign({ sub: userId }, refreshSecret, {
    expiresIn: config.jwt.refreshExpires,
  } as SignOptions);
  return { accessToken, refreshToken };
}

export function hashToken(token: string): string {
  return bcrypt.hashSync(token, 10);
}

export function setAuthCookies(res: Response, accessToken: string, refreshToken: string) {
  const isProd = config.nodeEnv === 'production';
  res.cookie('access_token', accessToken, {
    httpOnly: true,
    secure: isProd,
    sameSite: isProd ? 'none' : 'lax',
    maxAge: 15 * 60 * 1000,
    path: '/',
  });
  res.cookie('refresh_token', refreshToken, {
    httpOnly: true,
    secure: isProd,
    sameSite: isProd ? 'none' : 'lax',
    maxAge: 7 * 24 * 60 * 60 * 1000,
    path: '/',
  });
}
