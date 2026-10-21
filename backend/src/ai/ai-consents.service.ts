import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { AiActionError } from './ai-errors';

/**
 * HELM AI Phase 3 — Consentements granulaires (D17 §1, D17.6).
 *
 * Principe : l'accès aux données sensibles est REFUSÉ PAR DÉFAUT. Un
 * périmètre sensible n'entre dans le contexte du modèle QUE si :
 *   1. l'utilisateur a activé le module dans ses préférences (contextScope) ;
 *   2. ET il a accordé un consentement EXPLICITE dédié (AiConsent).
 *
 * Chaque octroi / retrait est journalisé (piste d'audit minimisée) et le
 * retrait est effectif immédiatement : le Policy Engine relit les
 * consentements à chaque demande, sans cache.
 */

export interface ConsentScopeDef {
  scope: string; // identifiant stable
  module: string; // module LifeHelm concerné
  label: string; // libellé affiché
  description: string; // ce qui est transmis EXACTEMENT, sans jargon
}

/** Catalogue des périmètres sensibles (D17 §1 — jamais d'ajout implicite). */
export const CONSENT_SCOPES: readonly ConsentScopeDef[] = [
  {
    scope: 'wellbeing.journal',
    module: 'wellbeing',
    label: 'Journal de bien-être',
    description:
      'Tendances d\'humeur, d\'énergie et de stress des 14 derniers jours (scores moyens, jamais le texte de vos notes).',
  },
  {
    scope: 'messaging.read',
    module: 'messaging',
    label: 'Messagerie',
    description:
      'Volume de messages non lus et conversations actives (comptages, jamais le contenu des messages).',
  },
  {
    scope: 'notes.content',
    module: 'notes',
    label: 'Contenu des notes',
    description:
      'Titres et extraits de vos notes récentes (recherche approfondie dans vos notes).',
  },
] as const;

/** Association module → consentement requis (source de vérité du Policy Engine). */
export const MODULE_CONSENT: Readonly<Record<string, string>> = {
  notes: 'notes.content',
  wellbeing: 'wellbeing.journal',
  messaging: 'messaging.read',
};

@Injectable()
export class AiConsentsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Catalogue + état courant de chaque périmètre pour l'utilisateur. */
  async list(userId: string) {
    const rows = await this.prisma.aiConsent.findMany({ where: { userId } });
    const byScope = new Map(rows.map((r) => [r.scope, r]));
    return {
      scopes: CONSENT_SCOPES.map((def) => {
        const row = byScope.get(def.scope);
        return {
          ...def,
          granted: row?.granted ?? false,
          grantedAt: row?.grantedAt ?? null,
          revokedAt: row?.revokedAt ?? null,
        };
      }),
    };
  }

  /** Octroi / retrait explicite — journalisé, effectif immédiatement. */
  async set(userId: string, scope: string, granted: boolean, ip?: string) {
    const def = CONSENT_SCOPES.find((c) => c.scope === scope);
    if (!def) {
      throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'Périmètre de consentement inconnu.');
    }
    const now = new Date();
    const row = await this.prisma.aiConsent.upsert({
      where: { userId_scope: { userId, scope } },
      create: {
        userId,
        scope,
        granted,
        grantedAt: granted ? now : null,
        revokedAt: granted ? null : now,
      },
      update: {
        granted,
        grantedAt: granted ? now : null,
        revokedAt: granted ? null : now,
      },
    });

    await this.prisma.aiAuditEvent.create({
      data: {
        userId,
        action: granted ? 'CONSENT_GRANTED' : 'CONSENT_REVOKED',
        entity: scope,
        details: { module: def.module } as unknown as Prisma.InputJsonValue,
        ip: ip ?? null,
      },
    });

    return { scope, granted: row.granted, grantedAt: row.grantedAt, revokedAt: row.revokedAt };
  }

  /** Scopes actuellement accordés — consulté par le Policy Engine à chaque demande. */
  async grantedScopes(userId: string): Promise<Set<string>> {
    const rows = await this.prisma.aiConsent.findMany({
      where: { userId, granted: true },
      select: { scope: true },
    });
    return new Set(rows.map((r) => r.scope));
  }
}
