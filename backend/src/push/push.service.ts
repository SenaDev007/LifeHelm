import { Injectable, Logger } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Notifications push natives (D17.6) — envoi via FCM HTTP v1.
 *
 * Implémentation volontairement sans firebase-admin (qui embarque toute la
 * surface Firebase) : l'API v1 est un simple appel OAuth2 + POST, cohérent
 * avec le pattern « fetch natif » du projet (cf. nvidia.provider.ts).
 *
 * Mode honnête : sans credentials Firebase (FIREBASE_PROJECT_ID, CLIENT_EMAIL,
 * PRIVATE_KEY), le service répond DEGRADED et n'envoie rien — jamais d'échec
 * silencieux, jamais de crash du briefing à cause du push. L'envoi est
 * TOUJOURS best-effort : les erreurs FCM sont journalisées et les jetons
 * invalidés (UNREGISTERED) sont désactivés automatiquement.
 */

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';

interface FcmTarget {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface SendReport {
  sent: number;
  failed: number;
  removedDevices: number;
  degraded: boolean;
}

@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);

  /** Cache du jeton d'accès OAuth2 (durée de vie 1 h — rafraîchi à J-10 min). */
  private accessToken: { token: string; expiresAt: number } | null = null;

  constructor(private readonly prisma: PrismaService) {}

  // ─────────────────────────── Configuration ───────────────────────────

  private projectId(): string | null {
    return process.env.FIREBASE_PROJECT_ID?.trim() || null;
  }

  private clientEmail(): string | null {
    return process.env.FIREBASE_CLIENT_EMAIL?.trim() || null;
  }

  private privateKey(): string | null {
    const raw = process.env.FIREBASE_PRIVATE_KEY?.trim();
    if (!raw) return null;
    // Railway/CI stockent souvent les sauts de ligne échappés (\n littéraux).
    return raw.includes('\\n') ? raw.replace(/\\n/g, '\n') : raw;
  }

  /** FCM configuré ? (les 3 variables présence — jamais leur contenu). */
  isConfigured(): boolean {
    return Boolean(this.projectId() && this.clientEmail() && this.privateKey());
  }

  /** Statut public — aucun secret n'est exposé. */
  async status(userId: string) {
    const devices = await this.prisma.pushDevice.count({ where: { userId, active: true } });
    return {
      provider: 'FCM' as const,
      configured: this.isConfigured(),
      mode: this.isConfigured() ? ('READY' as const) : ('DEGRADED' as const),
      activeDevices: devices,
    };
  }

  // ─────────────────────────── Appareils ───────────────────────────

  /** Enregistre (ou rafraîchit) un appareil — upsert par jeton FCM. */
  async registerDevice(
    userId: string,
    input: { token: string; platform: string; deviceId?: string; appVersion?: string },
  ) {
    const device = await this.prisma.pushDevice.upsert({
      where: { token: input.token },
      create: { userId, ...input },
      update: {
        // Rotation de jeton : FCM garantit l'unicité mondiale du jeton —
        // un upsert sur le même jeton réattribue la propriété à l'appelant
        // légitime (le détenteur du compte qui présente le jeton).
        userId,
        platform: input.platform,
        deviceId: input.deviceId,
        appVersion: input.appVersion,
        active: true,
        lastSeenAt: new Date(),
      },
    });
    return this.maskDevice(device);
  }

  /** Liste des appareils de l'utilisateur (jeton masqué). */
  async listDevices(userId: string) {
    const devices = await this.prisma.pushDevice.findMany({
      where: { userId },
      orderBy: { lastSeenAt: 'desc' },
      take: 20,
    });
    return devices.map((d) => this.maskDevice(d));
  }

  async removeDevice(userId: string, id: string) {
    const device = await this.prisma.pushDevice.findFirst({ where: { id, userId } });
    if (!device) return null;
    await this.prisma.pushDevice.delete({ where: { id } });
    return { deleted: true };
  }

  /** Représentation publique d'un appareil — le jeton n'est jamais en clair. */
  private maskDevice(d: {
    id: string; platform: string; deviceId: string | null; appVersion: string | null;
    active: boolean; lastSeenAt: Date; createdAt: Date; token: string;
  }) {
    const t = d.token;
    return {
      id: d.id,
      platform: d.platform,
      tokenPreview: `${t.slice(0, 8)}…${t.slice(-4)}`,
      deviceId: d.deviceId,
      appVersion: d.appVersion,
      active: d.active,
      lastSeenAt: d.lastSeenAt,
      createdAt: d.createdAt,
    };
  }

  // ─────────────────────────── Envoi ───────────────────────────

  /**
   * Envoie une notification à TOUS les appareils actifs de l'utilisateur.
   * Best-effort : aucune erreur d'envoi ne remonte (juste journalisée).
   */
  async sendToUser(userId: string, target: FcmTarget): Promise<SendReport> {
    if (!this.isConfigured()) {
      return { sent: 0, failed: 0, removedDevices: 0, degraded: true };
    }
    const devices = await this.prisma.pushDevice.findMany({
      where: { userId, active: true },
      select: { id: true, token: true },
      take: 20,
    });
    if (devices.length === 0) {
      return { sent: 0, failed: 0, removedDevices: 0, degraded: false };
    }
    let sent = 0;
    let failed = 0;
    const invalidated: string[] = [];
    for (const d of devices) {
      const outcome = await this.sendOne(d.token, target);
      if (outcome === 'SENT') sent++;
      else {
        failed++;
        if (outcome === 'UNREGISTERED' || outcome === 'INVALID_TOKEN') invalidated.push(d.id);
      }
    }
    let removedDevices = 0;
    if (invalidated.length > 0) {
      const res = await this.prisma.pushDevice.updateMany({
        where: { id: { in: invalidated }, userId },
        data: { active: false },
      });
      removedDevices = res.count;
      this.logger.log(`${removedDevices} appareil(s) push invalidé(s) par FCM`);
    }
    return { sent, failed, removedDevices, degraded: false };
  }

  /** Envoi d'un message : SENT | UNREGISTERED | INVALID_TOKEN | ERROR. */
  private async sendOne(
    token: string,
    target: FcmTarget,
  ): Promise<'SENT' | 'UNREGISTERED' | 'INVALID_TOKEN' | 'ERROR'> {
    try {
      const accessToken = await this.getAccessToken();
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${this.projectId()}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: target.title, body: target.body },
              data: target.data ?? {},
              android: {
                priority: 'HIGH',
                notification: { channel_id: 'helm_briefing', default_sound: true, default_vibrate_timings: true },
              },
              apns: { payload: { aps: { sound: 'default' } } },
            },
          }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      if (res.ok) return 'SENT';
      const body = (await res.json().catch(() => ({}))) as {
        error?: { details?: Array<{ reason?: string }> };
      };
      const reasons = (body.error?.details ?? []).map((x) => x.reason).join(',');
      if (res.status === 404 || reasons.includes('UNREGISTERED')) return 'UNREGISTERED';
      if (res.status === 400) return 'INVALID_TOKEN';
      this.logger.warn(`FCM ${res.status} : ${reasons || 'sans détail'}`.slice(0, 160));
      return 'ERROR';
    } catch (e) {
      this.logger.warn(`FCM indisponible : ${String(e).slice(0, 120)}`);
      return 'ERROR';
    }
  }

  // ─────────────────────────── OAuth2 (JWT RS256 → access token) ───────────────────────────

  private async getAccessToken(): Promise<string> {
    if (this.accessToken && this.accessToken.expiresAt > Date.now() + 10 * 60_000) {
      return this.accessToken.token;
    }
    const now = Math.floor(Date.now() / 1000);
    const assertion = jwt.sign(
      {
        iss: this.clientEmail(),
        scope: FCM_SCOPE,
        aud: OAUTH_TOKEN_URL,
        iat: now,
        exp: now + 3600,
      },
      this.privateKey()!,
      { algorithm: 'RS256' },
    );
    const res = await fetch(OAUTH_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) {
      throw new Error(`OAUTH_FCM_${res.status}`);
    }
    const data = (await res.json()) as { access_token: string; expires_in: number };
    this.accessToken = { token: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
    return data.access_token;
  }

  // ─────────────────────────── Briefing ───────────────────────────

  /**
   * Notification « briefing du jour prêt » — appelée après la génération
   * AUTOMATIQUE (cron) uniquement : une génération à la demande signifie que
   * l'utilisateur est déjà dans l'application (aucune notification).
   */
  async sendBriefingPush(
    userId: string,
    briefing: { headline: string; alertCount: number; date: string },
  ): Promise<SendReport> {
    const body =
      briefing.alertCount > 0
        ? `${briefing.headline} · ${briefing.alertCount} alerte(s) à consulter`
        : briefing.headline;
    const report = await this.sendToUser(userId, {
      title: 'LifeHelm — Briefing du jour',
      body: body.slice(0, 178),
      data: {
        route: 'briefing',
        date: briefing.date,
        alertCount: String(briefing.alertCount),
      },
    });
    if (report.degraded) {
      this.logger.log('Push briefing ignoré (FCM non configuré — mode honnête)');
    } else if (report.sent > 0) {
      this.logger.log(`Push briefing envoyé à ${report.sent} appareil(s)`);
    }
    return report;
  }
}
