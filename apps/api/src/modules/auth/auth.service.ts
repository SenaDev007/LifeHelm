import { BadRequestException, ConflictException, Injectable, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { ConfigService } from "@nestjs/config";
import { Response, Request } from "express";
import bcrypt from "bcrypt";
import crypto from "crypto";
import { prisma } from "@lifehelm/database";
import { RegisterDto } from "./dto/register.dto";
import { LoginDto } from "./dto/login.dto";

type TokenPair = { accessToken: string; refreshTokenRaw: string };

function getCookieRefreshToken(req: Request) {
  // cookie-parser populates req.cookies
  const cookies = (req as unknown as { cookies?: Record<string, string> }).cookies;
  return cookies?.refreshToken ?? null;
}

function sha256Hex(input: string) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

function generateRefreshTokenRaw() {
  return crypto.randomBytes(48).toString("base64url");
}

function getCookieOptions(config: ConfigService) {
  const secure = config.get<string>("NODE_ENV") === "production";
  const sameSite = config.get<string>("COOKIE_SAME_SITE") ?? "strict";
  return {
    httpOnly: true,
    secure,
    sameSite: sameSite as "strict" | "lax" | "none",
    path: "/auth/refresh",
    // maxAge est en ms
    maxAge: config.get<string>("JWT_REFRESH_EXPIRES_MS") ? Number(config.get<string>("JWT_REFRESH_EXPIRES_MS")) : 7 * 24 * 60 * 60 * 1000,
  };
}

@Injectable()
export class AuthService {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService
  ) {}

  private async createAccessToken(userId: string, plan: string, uiMode: string) {
    const payload = { sub: userId, plan, uiMode };
    return this.jwt.signAsync(payload);
  }

  private async createRefreshToken(userId: string) {
    const refreshTokenRaw = generateRefreshTokenRaw();
    const refreshTokenHash = sha256Hex(refreshTokenRaw);

    // rotation friendly: on login/register create a session
    const session = await prisma.session.create({
      data: {
        userId,
        deviceType: "mobile",
        lastActiveAt: new Date(),
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    await prisma.refreshToken.create({
      data: {
        userId,
        token: refreshTokenHash,
        sessionId: session.id,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });

    return { refreshTokenRaw };
  }

  async register(dto: RegisterDto, res: Response) {
    const existing = await prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException("Email déjà utilisé");

    const passwordHash = await bcrypt.hash(dto.password, 12);
    const user = await prisma.user.create({
      data: {
        name: dto.name,
        email: dto.email,
        passwordHash,
        currency: dto.currency,
        language: dto.language,
        uiMode: dto.uiMode,
        plan: dto.plan,
      },
      select: { id: true, name: true, email: true, plan: true, uiMode: true },
    });

    const accessToken = await this.createAccessToken(user.id, user.plan, user.uiMode);
    const { refreshTokenRaw } = await this.createRefreshToken(user.id);
    res.cookie("refreshToken", refreshTokenRaw, getCookieOptions(this.config));

    return {
      success: true,
      user: { id: user.id, name: user.name },
      accessToken,
    };
  }

  async login(dto: LoginDto, res: Response) {
    const user = await prisma.user.findUnique({ where: { email: dto.email } });
    if (!user || !user.passwordHash) throw new UnauthorizedException("Email ou mot de passe incorrect");

    const ok = await bcrypt.compare(dto.password, user.passwordHash);
    if (!ok) throw new UnauthorizedException("Email ou mot de passe incorrect");

    const accessToken = await this.createAccessToken(user.id, user.plan, user.uiMode);
    const { refreshTokenRaw } = await this.createRefreshToken(user.id);
    res.cookie("refreshToken", refreshTokenRaw, getCookieOptions(this.config));

    return {
      success: true,
      user: { id: user.id, name: user.name },
      accessToken,
    };
  }

  async refresh(req: Request, res: Response) {
    const refreshTokenRaw = getCookieRefreshToken(req);
    if (!refreshTokenRaw) throw new UnauthorizedException("Token de refresh manquant");

    const tokenHash = sha256Hex(refreshTokenRaw);
    const tokenRow = await prisma.refreshToken.findUnique({
      where: { token: tokenHash },
      include: { user: true, session: true },
    });
    if (!tokenRow || tokenRow.revokedAt) throw new UnauthorizedException("Token expiré");
    if (tokenRow.expiresAt.getTime() < Date.now()) throw new UnauthorizedException("Token expiré");
    if (tokenRow.usedAt) throw new UnauthorizedException("Token invalide");

    // rotation: revoke old + create new
    await prisma.refreshToken.update({
      where: { id: tokenRow.id },
      data: { usedAt: new Date() },
    });

    const user = tokenRow.user;
    const accessToken = await this.createAccessToken(user.id, user.plan, user.uiMode);
    const { refreshTokenRaw: newRaw } = await this.createRefreshToken(user.id);
    res.cookie("refreshToken", newRaw, getCookieOptions(this.config));

    return { success: true, accessToken };
  }

  async logout(req: Request, res: Response) {
    const refreshTokenRaw = getCookieRefreshToken(req);
    if (!refreshTokenRaw) throw new BadRequestException("Aucun token");

    const tokenHash = sha256Hex(refreshTokenRaw);
    const tokenRow = await prisma.refreshToken.findUnique({ where: { token: tokenHash } });
    if (tokenRow) {
      await prisma.refreshToken.update({
        where: { id: tokenRow.id },
        data: { revokedAt: new Date() },
      });
    }

    res.clearCookie("refreshToken", { path: "/auth/refresh" });
    return { success: true, message: "Déconnexion OK" };
  }

  async listSessions(req: Request) {
    const auth = (req as unknown as { user?: { id: string } }).user;
    if (!auth?.id) throw new UnauthorizedException("Non authentifié");
    return prisma.session.findMany({
      where: { userId: auth.id },
      orderBy: { lastActiveAt: "desc" },
      select: { id: true, deviceName: true, deviceType: true, lastActiveAt: true, expiresAt: true },
    });
  }
}

