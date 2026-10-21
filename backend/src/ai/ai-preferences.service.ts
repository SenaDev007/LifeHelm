import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AiActionError } from './ai-errors';

/**
 * HELM AI — Préférences et usage (D17.2 §7.2, §7.5).
 *
 * Préférences : le Policy Engine consulte `contextScope` AVANT de construire
 * le contexte envoyé au modèle — un module désactivé ici n'est tout
 * simplement pas transmis, quoi qu'il arrive (défense en profondeur).
 *
 * Usage : compteurs par fenêtre glissante 24 h — base des quotas et de la
 * transparence affichée dans l'application (« 12/60 messages aujourd'hui »).
 */

/** Quota journalier de messages (politique raisonnable, ajustable par env). */
const DAILY_MESSAGE_QUOTA = Number(process.env.AI_DAILY_MESSAGE_QUOTA ?? 60);

export const CONTEXT_SCOPES = ['finance', 'tasks', 'agenda', 'projects', 'notes', 'wellbeing', 'messaging'] as const;
export type ContextScope = (typeof CONTEXT_SCOPES)[number];

export const AUTONOMY_LEVELS = ['SUGGEST', 'PREPARE', 'ASSIST'] as const;
export const ALERT_THRESHOLDS = ['INFORMATION', 'NORMAL', 'IMPORTANT'] as const;

/** Périmètres sensibles : JAMAIS transmis au modèle, même si contextScope
 *  dit true (Phase 2) — un consentement explicite (AiConsent) sera requis
 *  pour les ouvrir en Phase 3. */
const ALWAYS_EXCLUDED: ContextScope[] = ['wellbeing', 'messaging'];

@Injectable()
export class AiPreferencesService {
  constructor(private readonly prisma: PrismaService) {}

  /** Préférences effectives — valeurs par défaut si aucune ligne. */
  async get(userId: string) {
    const pref = await this.prisma.aiPreference.findUnique({ where: { userId } });
    return {
      autonomyLevel: pref?.autonomyLevel ?? 'SUGGEST',
      alertThreshold: pref?.alertThreshold ?? 'NORMAL',
      contextScope: this.normalizeScope(pref?.contextScope),
      dailyBriefing: pref?.dailyBriefing ?? false,
      briefingHour: pref?.briefingHour ?? 7,
      language: pref?.language ?? 'fr',
      updatedAt: pref?.updatedAt ?? null,
    };
  }

  async update(userId: string, patch: {
    autonomyLevel?: string;
    alertThreshold?: string;
    contextScope?: Record<string, unknown>;
    dailyBriefing?: boolean;
    briefingHour?: number;
    language?: string;
  }, ip?: string) {
    const data: Prisma.AiPreferenceUpdateInput | Prisma.AiPreferenceUncheckedCreateInput = {};
    if (patch.autonomyLevel !== undefined) {
      if (!AUTONOMY_LEVELS.includes(patch.autonomyLevel as (typeof AUTONOMY_LEVELS)[number])) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'Niveau d\'autonomie inconnu (SUGGEST, PREPARE ou ASSIST).');
      }
      data.autonomyLevel = patch.autonomyLevel;
    }
    if (patch.alertThreshold !== undefined) {
      if (!ALERT_THRESHOLDS.includes(patch.alertThreshold as (typeof ALERT_THRESHOLDS)[number])) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'Seuil d\'alerte inconnu (INFORMATION, NORMAL ou IMPORTANT).');
      }
      data.alertThreshold = patch.alertThreshold;
    }
    if (patch.contextScope !== undefined) {
      data.contextScope = this.normalizeScope(patch.contextScope) as unknown as Prisma.InputJsonValue;
    }
    if (patch.dailyBriefing !== undefined) data.dailyBriefing = patch.dailyBriefing;
    if (patch.briefingHour !== undefined) {
      const h = Math.round(patch.briefingHour);
      if (h < 0 || h > 23) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'L\'heure du briefing doit être comprise entre 0 et 23.');
      }
      data.briefingHour = h;
    }
    if (patch.language !== undefined) data.language = patch.language.slice(0, 8);

    const pref = await this.prisma.aiPreference.upsert({
      where: { userId },
      create: { userId, ...data } as Prisma.AiPreferenceUncheckedCreateInput,
      update: data as Prisma.AiPreferenceUpdateInput,
    });

    await this.prisma.aiAuditEvent.create({
      data: {
        userId,
        action: 'PREFS_UPDATED',
        entity: 'ai-preferences',
        details: { keys: Object.keys(patch) } as unknown as Prisma.InputJsonValue,
        ip: ip ?? null,
      },
    });

    return {
      autonomyLevel: pref.autonomyLevel,
      alertThreshold: pref.alertThreshold,
      contextScope: this.normalizeScope(pref.contextScope),
      dailyBriefing: pref.dailyBriefing,
      briefingHour: pref.briefingHour,
      language: pref.language,
      updatedAt: pref.updatedAt,
    };
  }

  /**
   * Périmètre effectif du contexte — intersection préférences × exclusions
   * de sécurité. C'est LA fonction que l'orchestrateur consulte avant chaque
   * appel au modèle (défense en profondeur : même un bug de prompt ne peut
   * pas transmettre un module exclu).
   */
  async effectiveScope(userId: string): Promise<Record<ContextScope, boolean>> {
    const pref = await this.prisma.aiPreference.findUnique({ where: { userId } });
    const scope = this.normalizeScope(pref?.contextScope);
    for (const excluded of ALWAYS_EXCLUDED) scope[excluded] = false;
    return scope;
  }

  private normalizeScope(raw: unknown): Record<ContextScope, boolean> {
    const scope = raw && typeof raw === 'object' ? (raw as Record<string, unknown>) : {};
    const result = {} as Record<ContextScope, boolean>;
    for (const key of CONTEXT_SCOPES) {
      result[key] = key === 'notes' ? scope[key] === true : scope[key] !== false; // défaut: activé sauf notes/wellbeing/messaging
    }
    result.wellbeing = false;
    result.messaging = false;
    return result;
  }

  // ─────────────────────── Usage & quotas ───────────────────────

  async recordMessage(userId: string, modelKey: string | null, latencyMs: number, tokens?: { in?: number; out?: number }) {
    await this.prisma.aiUsageRecord.create({
      data: {
        userId,
        kind: 'MESSAGE',
        modelKey,
        latencyMs,
        tokensIn: tokens?.in ?? 0,
        tokensOut: tokens?.out ?? 0,
      },
    });
  }

  async usage(userId: string) {
    const since24h = new Date(Date.now() - 24 * 3_600_000);
    const since30d = new Date(Date.now() - 30 * 24 * 3_600_000);

    const [byKind24h, total30d, latency] = await Promise.all([
      this.prisma.aiUsageRecord.groupBy({
        by: ['kind'],
        where: { userId, createdAt: { gte: since24h } },
        _count: { _all: true },
      }),
      this.prisma.aiUsageRecord.count({ where: { userId, createdAt: { gte: since30d } } }),
      this.prisma.aiUsageRecord.aggregate({
        where: { userId, kind: 'MESSAGE', createdAt: { gte: since24h } },
        _avg: { latencyMs: true },
      }),
    ]);

    const counts = { MESSAGE: 0, ACTION_CONFIRM: 0, TOOL_EXECUTION: 0 } as Record<string, number>;
    for (const row of byKind24h) counts[row.kind] = row._count._all;

    return {
      window: '24h',
      messages: counts.MESSAGE ?? 0,
      messageQuota: DAILY_MESSAGE_QUOTA,
      actionsConfirmed: counts.ACTION_CONFIRM ?? 0,
      toolExecutions: counts.TOOL_EXECUTION ?? 0,
      averageLatencyMs: Math.round(latency._avg.latencyMs ?? 0),
      total30d,
    };
  }

  /** Dépassement de quota — l'orchestrateur refuse AVANT d'appeler le modèle. */
  async overQuota(userId: string): Promise<boolean> {
    const since24h = new Date(Date.now() - 24 * 3_600_000);
    const count = await this.prisma.aiUsageRecord.count({
      where: { userId, kind: 'MESSAGE', createdAt: { gte: since24h } },
    });
    return count >= DAILY_MESSAGE_QUOTA;
  }
}
