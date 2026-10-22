import {
  Injectable,
  HttpException,
  HttpStatus,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto, LoginDto } from './dto/auth.dto';
import { sha256hex, randomToken, randomDigits } from '../common/crypto.util';
import { generateTotpSecret, verifyTotp, otpauthUrl, currentTotp } from './totp.util';

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number; // secondes
}

export interface PublicUser {
  id: string;
  email: string | null;
  phone: string | null;
  firstName: string;
  lastName: string | null;
  avatarUrl: string | null;
  profession: string | null;
  country: string | null;
  emailVerifiedAt: string | null;
  phoneVerifiedAt: string | null;
  twoFactorEnabled: boolean;
  createdAt: string;
}

const isDev = process.env.NODE_ENV !== 'production';

@Injectable()
export class AuthService {
  private readonly logger = new Logger('AuthService');

  constructor(
    private prisma: PrismaService,
    private jwt: JwtService,
  ) {}

  // ─────────────────────────── Helpers ───────────────────────────

  private accessTtlSec(): number {
    return Number(process.env.ACCESS_TOKEN_TTL_MIN ?? 15) * 60;
  }

  private refreshExpiry(): Date {
    const days = Number(process.env.REFRESH_TOKEN_TTL_DAYS ?? 30);
    return new Date(Date.now() + days * 24 * 3600 * 1000);
  }

  public toPublicUser(u: {
    id: string; email: string | null; phone: string | null; firstName: string;
    lastName: string | null; avatarUrl: string | null; profession: string | null;
    country: string | null; emailVerifiedAt: Date | null;
    phoneVerifiedAt: Date | null; twoFactorEnabled: boolean; createdAt: Date;
  }): PublicUser {
    return {
      id: u.id,
      email: u.email,
      phone: u.phone,
      firstName: u.firstName,
      lastName: u.lastName,
      avatarUrl: u.avatarUrl,
      profession: u.profession,
      country: u.country,
      emailVerifiedAt: u.emailVerifiedAt?.toISOString() ?? null,
      phoneVerifiedAt: u.phoneVerifiedAt?.toISOString() ?? null,
      twoFactorEnabled: u.twoFactorEnabled,
      createdAt: u.createdAt.toISOString(),
    };
  }

  /** Normalise un téléphone : ne conserve que les chiffres, précédés de
   *  « + ». Le préfixe international « 00 » éventuel est converti. */
  private normalizePhone(phone: string): string {
    let digits = phone.replace(/[^0-9]/g, '');
    if (digits.startsWith('00')) digits = digits.slice(2);
    if (!digits) return phone.trim();
    return `+${digits}`;
  }

  /** Chiffres significatifs d'un identifiant téléphonique saisi (le « + »
   *  et le « 00 » éventuels sont neutralisés par normalizePhone/findUserCandidates). */
  private phoneDigits(input: string): string {
    let digits = input.replace(/[^0-9]/g, '');
    if (digits.startsWith('00')) digits = digits.slice(2);
    return digits;
  }

  /** Résout un identifiant (courriel OU téléphone) en candidats utilisateurs.
   *
   *  Téléphone — deux stratégies, dans l'ordre :
   *   1. correspondance exacte du numéro stocké (« +2290197… ») ;
   *   2. correspondance par suffixe : le numéro LOCAL saisi sans indicatif
   *      (ex. « 01 97 12 34 56 » au Bénin — 10 chiffres, ou « 97 12 34 56 »
   *      ancien format à 8 chiffres) retrouve le compte enregistré sous
   *      « +2290197… » / « +22997… », car le numéro stocké se TERMINE par
   *      les chiffres tapés.
   *
   *  Plusieurs candidats (suffixe partagé entre deux pays) sont renvoyés :
   *  l'appelant départage par mot de passe (login) ou prend le premier. */
  private async findUserCandidates(identifier: string) {
    const trimmed = identifier.trim();
    if (trimmed.includes('@')) {
      const byEmail = await this.prisma.user.findUnique({
        where: { email: trimmed.toLowerCase() },
      });
      return byEmail ? [byEmail] : [];
    }
    const digits = this.phoneDigits(trimmed);
    if (digits.length < 6) return [];

    // 1) Numéro complet saisi avec indicatif (+229… ou 229…).
    const exact = await this.prisma.user.findMany({
      where: { OR: [{ phone: `+${digits}` }, { phone: digits }] },
      take: 5,
    });
    if (exact.length > 0) return exact;

    // 2) Correspondance par suffixe — les deux sens sont couverts :
    //    a) saisie LOCALE plus courte que le numéro stocké (« 0197… »
    //       retrouve « +2290197… ») ;
    //    b) saisie AVEC indicatif plus longue qu'un numéro stocké en local
    //       (« +2290197… » retrouve « +0197… », formats 2024 à 10 chiffres
    //       et ancien à 8) — remonté par l'utilisateur v0.2.0.
    //    Min. 8 chiffres pour éviter les faux positifs ; les candidats
    //    multiples sont départagés par mot de passe (login).
    if (digits.length < 8) return [];
    const suffixes = [...new Set([digits, digits.slice(-10), digits.slice(-8)])]
      .filter((suffix) => suffix.length >= 8);
    return this.prisma.user.findMany({
      where: { OR: suffixes.map((suffix) => ({ phone: { endsWith: suffix } })) },
      take: 5,
    });
  }

  /** Crée une session (famille neuve) et le couple access/refresh. */
  private async issueSession(
    userId: string,
    familyId: string | null,
    meta: { deviceName?: string; userAgent?: string; ip?: string },
  ): Promise<SessionTokens> {
    const family = familyId ?? randomToken(12);
    const refreshToken = randomToken(48);
    const session = await this.prisma.session.create({
      data: {
        familyId: family,
        userId,
        refreshTokenHash: sha256hex(refreshToken),
        deviceName: meta.deviceName ?? null,
        userAgent: meta.userAgent ?? null,
        ip: meta.ip ?? null,
        expiresAt: this.refreshExpiry(),
      },
    });
    const accessToken = await this.jwt.signAsync({
      sub: userId,
      sid: session.id,
      fid: family,
      typ: 'access',
    });
    return { accessToken, refreshToken, expiresIn: this.accessTtlSec() };
  }

  /** Rotation : révoque l'ancienne session, en crée une nouvelle dans la même famille. */
  private async rotateSession(oldSessionId: string, userId: string, familyId: string): Promise<SessionTokens> {
    const refreshToken = randomToken(48);
    const next = await this.prisma.session.create({
      data: {
        familyId,
        userId,
        refreshTokenHash: sha256hex(refreshToken),
        expiresAt: this.refreshExpiry(),
      },
    });
    await this.prisma.session.update({
      where: { id: oldSessionId },
      data: { revokedAt: new Date(), replacedById: next.id },
    });
    const accessToken = await this.jwt.signAsync({
      sub: userId,
      sid: next.id,
      fid: familyId,
      typ: 'access',
    });
    return { accessToken, refreshToken, expiresIn: this.accessTtlSec() };
  }

  /**
   * Détection de rejeu (D01.3) : un refresh token révoqué présenté à nouveau
   * ⇒ compromission probable ⇒ révocation de TOUTE la famille de sessions.
   */
  private async revokeFamily(familyId: string, exceptSessionId?: string) {
    await this.prisma.session.updateMany({
      where: { familyId, revokedAt: null, ...(exceptSessionId ? { id: { not: exceptSessionId } } : {}) },
      data: { revokedAt: new Date() },
    });
  }

  // ─────────────────────────── Inscription ───────────────────────────

  async register(dto: RegisterDto, meta: { userAgent?: string; ip?: string }) {
    const email = dto.email?.trim().toLowerCase() || null;
    const phone = dto.phone ? this.normalizePhone(dto.phone) : null;

    // Cohérence E.164 souple : 8 à 15 chiffres après l'indicatif.
    if (phone && !/^\+\d{8,15}$/.test(phone)) {
      throw new HttpException(
        { code: 'INVALID_PHONE', message: 'Numéro de téléphone invalide — 8 à 15 chiffres attendus après l\'indicatif.' },
        HttpStatus.BAD_REQUEST,
      );
    }

    if (!email && !phone) {
      throw new HttpException(
        { code: 'CONTACT_REQUIRED', message: 'Renseignez un courriel ou un numéro de téléphone.' },
        HttpStatus.BAD_REQUEST,
      );
    }

    if (email && (await this.prisma.user.findUnique({ where: { email } }))) {
      throw new HttpException(
        { code: 'EMAIL_TAKEN', message: 'Un compte existe déjà avec ce courriel.' },
        HttpStatus.CONFLICT,
      );
    }
    if (phone && (await this.prisma.user.findUnique({ where: { phone } }))) {
      throw new HttpException(
        { code: 'PHONE_TAKEN', message: 'Un compte existe déjà avec ce numéro.' },
        HttpStatus.CONFLICT,
      );
    }

    const passwordHash = await bcrypt.hash(dto.password, Number(process.env.BCRYPT_ROUNDS ?? 10));

    // Codes de vérification (24 h) — hashés, révélés uniquement en mode dev
    let devVerificationCode: string | undefined;
    let emailVerifyCodeHash: string | undefined;
    let phoneVerifyCodeHash: string | undefined;
    if (email) {
      const code = randomDigits(6);
      emailVerifyCodeHash = sha256hex(code);
      if (isDev) devVerificationCode = code;
    }
    if (phone) {
      const code = randomDigits(6);
      phoneVerifyCodeHash = sha256hex(code);
      if (isDev && !devVerificationCode) devVerificationCode = code;
    }

    const expiresAt = new Date(Date.now() + Number(process.env.VERIFY_CODE_TTL_HOURS ?? 24) * 3600 * 1000);

    const user = await this.prisma.user.create({
      data: {
        email,
        phone,
        passwordHash,
        firstName: dto.firstName.trim(),
        lastName: dto.lastName?.trim() ?? null,
        profession: dto.profession?.trim() || null,
        country: dto.country?.trim().toUpperCase() || null,
        emailVerifyCodeHash,
        emailVerifyCodeExpiresAt: emailVerifyCodeHash ? expiresAt : null,
        phoneVerifyCodeHash,
        phoneVerifyCodeExpiresAt: phoneVerifyCodeHash ? expiresAt : null,
      },
    });

    const tokens = await this.issueSession(user.id, null, {
      deviceName: dto.deviceName,
      userAgent: meta.userAgent,
      ip: meta.ip,
    });

    this.logger.log(`Inscription utilisateur ${user.id}`);
    return {
      user: this.toPublicUser(user),
      ...tokens,
      ...(isDev && devVerificationCode ? { devVerificationCode } : {}),
    };
  }

  // ─────────────────────────── Connexion ───────────────────────────

  async login(dto: LoginDto, meta: { userAgent?: string; ip?: string }) {
    // Candidats : le téléphone peut être saisi en format local (sans
    // indicatif) — ex. « 01 97 12 34 56 » pour un compte « +2290197… ».
    // Le mot de passe départage d'éventuels suffixes partagés.
    const candidates = await this.findUserCandidates(dto.identifier);
    let user = null;
    for (const candidate of candidates) {
      if (await bcrypt.compare(dto.password, candidate.passwordHash)) {
        user = candidate;
        break;
      }
    }
    if (!user) {
      throw new HttpException(
        { code: 'INVALID_CREDENTIALS', message: 'Identifiants incorrects.' },
        HttpStatus.UNAUTHORIZED,
      );
    }

    // 2FA (D01.3) — TOTP
    if (user.twoFactorEnabled) {
      if (!dto.totpCode) {
        throw new HttpException(
          { code: 'TOTP_REQUIRED', message: 'Code de vérification requis.' },
          HttpStatus.PRECONDITION_REQUIRED, // 428
        );
      }
      if (!user.twoFactorSecret || !verifyTotp(user.twoFactorSecret, dto.totpCode)) {
        throw new HttpException(
          { code: 'TOTP_INVALID', message: 'Code de vérification invalide.' },
          HttpStatus.UNAUTHORIZED,
        );
      }
    }

    const tokens = await this.issueSession(user.id, null, {
      deviceName: dto.deviceName,
      userAgent: meta.userAgent,
      ip: meta.ip,
    });
    this.logger.log(`Connexion utilisateur ${user.id}`);
    return { user: this.toPublicUser(user), ...tokens };
  }

  // ─────────────────────────── Profil ───────────────────────────

  async updateProfile(
    userId: string,
    dto: {
      firstName?: string;
      lastName?: string;
      phone?: string;
      profession?: string;
      country?: string;
      avatarUrl?: string;
    },
  ) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();

    // Unicité du téléphone si modifié.
    if (dto.phone !== undefined) {
      const phone = dto.phone ? this.normalizePhone(dto.phone) : null;
      if (phone && !/^\+\d{8,15}$/.test(phone)) {
        throw new HttpException(
          { code: 'INVALID_PHONE', message: 'Numéro de téléphone invalide — 8 à 15 chiffres attendus après l\'indicatif.' },
          HttpStatus.BAD_REQUEST,
        );
      }
      if (phone && phone !== user.phone) {
        const clash = await this.prisma.user.findUnique({ where: { phone } });
        if (clash) {
          throw new HttpException(
            { code: 'PHONE_TAKEN', message: 'Ce numéro est déjà utilisé par un autre compte.' },
            HttpStatus.CONFLICT,
          );
        }
      }
    }

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: {
        ...(dto.firstName !== undefined ? { firstName: dto.firstName.trim() } : {}),
        ...(dto.lastName !== undefined ? { lastName: dto.lastName?.trim() || null } : {}),
        ...(dto.phone !== undefined
          ? { phone: dto.phone ? this.normalizePhone(dto.phone) : null }
          : {}),
        ...(dto.profession !== undefined ? { profession: dto.profession?.trim() || null } : {}),
        ...(dto.country !== undefined ? { country: dto.country?.trim().toUpperCase() || null } : {}),
        ...(dto.avatarUrl !== undefined ? { avatarUrl: dto.avatarUrl || null } : {}),
      },
    });
    return { user: this.toPublicUser(updated) };
  }

  /** Suppression DÉFINITIVE : sessions, ressources synchronisées et compte
   *  (cascades Prisma) — après vérification du mot de passe. */
  async deleteAccount(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    if (!(await bcrypt.compare(password, user.passwordHash))) {
      throw new HttpException(
        { code: 'INVALID_CREDENTIALS', message: 'Mot de passe incorrect.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.prisma.user.delete({ where: { id: userId } });
    this.logger.warn(`Compte ${userId} supprimé définitivement (demande utilisateur)`);
  }

  // ─────────────── Questions de sécurité (récupération) ───────────────

  /** Enregistre 1 à 3 questions avec réponses hachées sha256. */
  async setSecurityQuestions(
    userId: string,
    items: { question: string; answerHash: string }[],
  ) {
    const cleaned = items
      .filter((i) => i.question?.trim() && /^[a-f0-9]{64}$/.test(i.answerHash))
      .slice(0, 3);
    if (cleaned.length === 0) {
      throw new HttpException(
        { code: 'INVALID_QUESTIONS', message: 'Questions de sécurité invalides.' },
        HttpStatus.BAD_REQUEST,
      );
    }
    const securityQuestions = cleaned.map((i) => ({
      question: i.question.trim(),
      answerHash: i.answerHash,
    }));
    await this.prisma.user.update({
      where: { id: userId },
      data: { securityQuestions },
    });
  }

  /** Questions publiques d'un compte (sans les réponses). */
  async securityQuestionsOf(identifier: string) {
    const [user] = await this.findUserCandidates(identifier);
    if (!user?.securityQuestions || !Array.isArray(user.securityQuestions)) {
      return { questions: null };
    }
    const questions = (user.securityQuestions as { question: string }[]).map(
      (q) => q.question,
    );
    return { questions: questions.length > 0 ? questions : null };
  }

  /** Vérifie les réponses (hashes sha256) — succès ⇒ jeton de
   *  réinitialisation identique au flux « mot de passe oublié ». */
  async recoverBySecurityQuestions(
    identifier: string,
    answers: Record<string, string>,
  ) {
    const [user] = await this.findUserCandidates(identifier);
    if (
      !user?.securityQuestions ||
      !Array.isArray(user.securityQuestions)
    ) {
      throw new HttpException(
        { code: 'NO_QUESTIONS', message: 'Aucune question de sécurité définie pour ce compte.' },
        HttpStatus.NOT_FOUND,
      );
    }
    const stored = user.securityQuestions as { question: string; answerHash: string }[];

    // Chaque réponse fournie doit correspondre au hash enregistré,
    // position par position — et TOUTES les questions doivent être couvertes.
    let ok = stored.length > 0;
    for (let i = 0; i < stored.length; i++) {
      const given = answers[String(i)] ?? answers[`${i}`] ?? '';
      if (!/^[a-f0-9]{64}$/.test(given) || given !== stored[i].answerHash) {
        ok = false;
        break;
      }
    }
    if (!ok) {
      this.logger.warn(`Échec de récupération par questions pour ${user.id}`);
      throw new HttpException(
        { code: 'INVALID_ANSWERS', message: 'Réponses incorrectes.' },
        HttpStatus.UNAUTHORIZED,
      );
    }

    const resetToken = randomToken(32);
    await this.prisma.user.update({
      where: { id: user.id },
      data: {
        resetTokenHash: sha256hex(resetToken),
        resetTokenExpiresAt: new Date(
          Date.now() + Number(process.env.RESET_TOKEN_TTL_MIN ?? 30) * 60 * 1000,
        ),
      },
    });
    this.logger.log(`Récupération par questions de sécurité réussie pour ${user.id}`);
    return { resetToken };
  }

  // ─────────────────────── Renouvellement (rotation) ───────────────────────

  async refresh(refreshToken: string) {
    const hash = sha256hex(refreshToken);
    const session = await this.prisma.session.findUnique({ where: { refreshTokenHash: hash } });

    if (!session) {
      throw new HttpException(
        { code: 'INVALID_TOKEN', message: 'Session introuvable.' },
        HttpStatus.UNAUTHORIZED,
      );
    }

    if (session.revokedAt) {
      // Rejeu d'un jeton déjà tourné ⇒ compromission ⇒ toute la famille tombe.
      await this.revokeFamily(session.familyId);
      this.logger.warn(`Rejeu détecté — famille ${session.familyId} révoquée`);
      throw new HttpException(
        { code: 'TOKEN_REUSED', message: 'Session révoquée (réutilisation détectée). Reconnectez-vous.' },
        HttpStatus.UNAUTHORIZED,
      );
    }

    if (session.expiresAt <= new Date()) {
      await this.revokeFamily(session.familyId);
      throw new HttpException(
        { code: 'INVALID_TOKEN', message: 'Session expirée.' },
        HttpStatus.UNAUTHORIZED,
      );
    }

    const tokens = await this.rotateSession(session.id, session.userId, session.familyId);
    return tokens;
  }

  // ─────────────────────────── Déconnexion ───────────────────────────

  async logout(refreshToken: string) {
    const hash = sha256hex(refreshToken);
    await this.prisma.session.updateMany({
      where: { refreshTokenHash: hash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  async logoutAll(userId: string) {
    await this.prisma.session.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  // ─────────────────────────── Profil / sessions ───────────────────────────

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    return { user: this.toPublicUser(user) };
  }

  async listSessions(userId: string, currentFamilyId: string) {
    const sessions = await this.prisma.session.findMany({
      where: { userId, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { lastUsedAt: 'desc' },
    });
    return {
      sessions: sessions.map((s) => ({
        id: s.id,
        familyId: s.familyId,
        deviceName: s.deviceName ?? 'Appareil inconnu',
        ip: s.ip,
        createdAt: s.createdAt.toISOString(),
        lastUsedAt: s.lastUsedAt.toISOString(),
        expiresAt: s.expiresAt.toISOString(),
        current: s.familyId === currentFamilyId,
      })),
    };
  }

  async revokeSession(userId: string, sessionId: string) {
    // On ne révoque que les sessions du demandeur (permissions §20.1)
    const session = await this.prisma.session.findFirst({ where: { id: sessionId, userId } });
    if (!session) {
      throw new HttpException(
        { code: 'NOT_FOUND', message: 'Session introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    await this.revokeFamily(session.familyId);
  }

  // ─────────────────────────── Mot de passe ───────────────────────────

  async changePassword(userId: string, currentPassword: string, newPassword: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    if (!(await bcrypt.compare(currentPassword, user.passwordHash))) {
      throw new HttpException(
        { code: 'INVALID_CREDENTIALS', message: 'Mot de passe actuel incorrect.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    const passwordHash = await bcrypt.hash(newPassword, Number(process.env.BCRYPT_ROUNDS ?? 10));
    // Réinitialisation ⇒ révocation des sessions existantes (D01.3 recommandé)
    await this.prisma.$transaction([
      this.prisma.user.update({ where: { id: userId }, data: { passwordHash } }),
      this.prisma.session.updateMany({
        where: { userId, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);
  }

  async forgotPassword(identifier: string) {
    const [user] = await this.findUserCandidates(identifier);

    // Anti-énumération : réponse identique que le compte existe ou non (202).
    if (!user) return { ...(isDev ? { devResetToken: null } : {}) };

    const resetToken = randomToken(32);
    const expiresAt = new Date(Date.now() + Number(process.env.RESET_TOKEN_TTL_MIN ?? 30) * 60 * 1000);
    await this.prisma.user.update({
      where: { id: user.id },
      data: { resetTokenHash: sha256hex(resetToken), resetTokenExpiresAt: expiresAt },
    });
    // Production : envoi par courriel/SMS (fournisseur à arbitrer, CDC §6.3)
    this.logger.log(`Demande de réinitialisation pour ${user.id}`);
    return { ...(isDev ? { devResetToken: resetToken } : {}) };
  }

  async resetPassword(resetToken: string, newPassword: string) {
    const user = await this.prisma.user.findFirst({
      where: { resetTokenHash: sha256hex(resetToken) },
    });
    if (!user || !user.resetTokenExpiresAt || user.resetTokenExpiresAt <= new Date()) {
      throw new HttpException(
        { code: 'INVALID_TOKEN', message: 'Lien de réinitialisation invalide ou expiré.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    const passwordHash = await bcrypt.hash(newPassword, Number(process.env.BCRYPT_ROUNDS ?? 10));
    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: user.id },
        data: { passwordHash, resetTokenHash: null, resetTokenExpiresAt: null },
      }),
      // Révocation de toutes les sessions après réinitialisation (D01.3)
      this.prisma.session.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
    ]);
  }

  // ─────────────────────────── 2FA TOTP ───────────────────────────

  async setup2fa(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    if (user.twoFactorEnabled) {
      throw new HttpException(
        { code: 'ALREADY_ENABLED', message: 'La double authentification est déjà activée.' },
        HttpStatus.CONFLICT,
      );
    }
    const secret = generateTotpSecret();
    // Stocké (non activé tant que le code n'est pas confirmé)
    await this.prisma.user.update({ where: { id: userId }, data: { twoFactorSecret: secret } });
    return { secret, otpauthUrl: otpauthUrl(secret, user.email ?? user.phone ?? user.id) };
  }

  async enable2fa(userId: string, totpCode: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.twoFactorSecret) {
      throw new HttpException(
        { code: 'SETUP_REQUIRED', message: 'Lancez d’abord la configuration.' },
        HttpStatus.BAD_REQUEST,
      );
    }
    if (!verifyTotp(user.twoFactorSecret, totpCode)) {
      throw new HttpException(
        { code: 'TOTP_INVALID', message: 'Code invalide, réessayez.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: true },
    });
  }

  async disable2fa(userId: string, totpCode: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user?.twoFactorEnabled || !user.twoFactorSecret) {
      throw new HttpException(
        { code: 'NOT_ENABLED', message: 'La double authentification n’est pas activée.' },
        HttpStatus.BAD_REQUEST,
      );
    }
    if (!verifyTotp(user.twoFactorSecret, totpCode)) {
      throw new HttpException(
        { code: 'TOTP_INVALID', message: 'Code invalide.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { twoFactorEnabled: false, twoFactorSecret: null },
    });
  }

  /** Debug/dev uniquement : code TOTP courant (jamais exposé en production). */
  currentCode(userId: string): string | null {
    void userId; // le secret est en base — exposé seulement via NODE_ENV=development dans un futur endpoint admin
    return null;
  }

  // ─────────────────── Vérification courriel / téléphone ───────────────────

  async verifyEmail(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    if (user.emailVerifiedAt) return; // déjà vérifié
    if (
      !user.emailVerifyCodeHash ||
      !user.emailVerifyCodeExpiresAt ||
      user.emailVerifyCodeExpiresAt <= new Date() ||
      user.emailVerifyCodeHash !== sha256hex(code)
    ) {
      throw new HttpException(
        { code: 'INVALID_CODE', message: 'Code de vérification invalide ou expiré.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { emailVerifiedAt: new Date(), emailVerifyCodeHash: null, emailVerifyCodeExpiresAt: null },
    });
  }

  async verifyPhone(userId: string, code: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new UnauthorizedException();
    if (user.phoneVerifiedAt) return;
    if (
      !user.phoneVerifyCodeHash ||
      !user.phoneVerifyCodeExpiresAt ||
      user.phoneVerifyCodeExpiresAt <= new Date() ||
      user.phoneVerifyCodeHash !== sha256hex(code)
    ) {
      throw new HttpException(
        { code: 'INVALID_CODE', message: 'Code de vérification invalide ou expiré.' },
        HttpStatus.UNAUTHORIZED,
      );
    }
    await this.prisma.user.update({
      where: { id: userId },
      data: { phoneVerifiedAt: new Date(), phoneVerifyCodeHash: null, phoneVerifyCodeExpiresAt: null },
    });
  }

  /** Génère un code TOTP de test — utilisé par le smoke test. */
  totpNow(secret: string): string {
    return currentTotp(secret);
  }
}
