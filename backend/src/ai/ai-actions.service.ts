import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { AiActionError } from './ai-errors';

/**
 * HELM AI — Actions confirmées (D17.2 §6, D17.4 §5.3).
 *
 * Principes :
 *  1. L'IA PROPOSE, l'utilisateur CONFIRME — aucune écriture métier sans
 *     confirmation explicite portant le hash du payload proposé.
 *  2. Idempotence stricte : la clé vient du client (UUID par tentative) ;
 *     un rejeu identique renvoie la réponse d'origine, un rejeu divergent
 *     est refusé (AI_ACTION_ALREADY_PROCESSED).
 *  3. Revalidation avant exécution (REVALIDATING) : les paramètres sont
 *     revérifiés au moment T de la confirmation — une référence disparue
 *     (compte supprimé, événement déplacé) échoue proprement.
 *  4. Les écritures passent par Resource + SyncChange : le mobile récupère
 *     les brouillons par le canal de synchronisation habituel (pull par
 *     curseur, D01.4) — jamais par un canal parallèle.
 *  5. Audit minimisé : AiAuditEvent ne journalise QUE le verbe et l'entité,
 *     jamais le contenu métier complet.
 */

const CONFIRM_WINDOW_MINUTES = 15;
const IDEMPOTENCY_TTL_HOURS = 24;
const AI_DEVICE = 'helm-ai';

export const AI_ACTION_TYPES = [
  'CREATE_TASK_DRAFT',
  'PROPOSE_EVENT_CHANGE',
  'PROPOSE_FINANCIAL_CORRECTION',
] as const;
export type AiActionType = (typeof AI_ACTION_TYPES)[number];

export interface ProposedActionInput {
  actionType: string;
  title: string;
  payload: Record<string, unknown>;
  summary?: string;
  safetyFlags?: string[];
}

@Injectable()
export class AiActionsService {
  private readonly logger = new Logger(AiActionsService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ─────────────────────── Utilitaires ───────────────────────

  /** Hash canonique du payload — comparé à la confirmation (STALE). */
  static hashPayload(payload: Record<string, unknown>): string {
    const canonical = JSON.stringify(payload, Object.keys(payload).sort());
    return createHash('sha256').update(canonical).digest('hex');
  }

  private async audit(
    userId: string,
    action: string,
    entity: string | null,
    details?: Record<string, unknown>,
    ip?: string,
  ) {
    await this.prisma.aiAuditEvent.create({
      data: {
        userId,
        action,
        entity,
        details: (details ?? undefined) as unknown as Prisma.InputJsonValue,
        ip: ip ?? null,
      },
    });
  }

  private async recordUsage(userId: string, kind: string, latencyMs: number) {
    await this.prisma.aiUsageRecord.create({ data: { userId, kind, latencyMs } });
  }

  /** Expiration paresseuse : une action en attente au-delà de la fenêtre
   *  est marquée EXPIRED dès qu'on la lit (aucun cron requis). */
  private async expireIfDue(id: string, expiresAt: Date, userId: string): Promise<boolean> {
    if (expiresAt.getTime() <= Date.now()) {
      await this.prisma.aiAction.update({ where: { id }, data: { status: 'EXPIRED' } });
      await this.audit(userId, 'ACTION_EXPIRED', id);
      return true;
    }
    return false;
  }

  // ─────────────────────── Création (depuis la réponse IA) ───────────────────────

  /**
   * Matérialise une proposition du modèle en AiAction AWAITING_CONFIRMATION.
   * Appelé par l'orchestrateur après validation de la sortie — jamais par
   * une route publique.
   */
  async propose(
    userId: string,
    conversationId: string | null,
    proposal: ProposedActionInput,
  ) {
    const actionType = AI_ACTION_TYPES.includes(proposal.actionType as AiActionType)
      ? (proposal.actionType as AiActionType)
      : null;
    if (!actionType) return null;

    const payload = this.sanitizePayload(actionType, proposal.payload);
    if (!payload) return null;

    const expiresAt = new Date(Date.now() + CONFIRM_WINDOW_MINUTES * 60_000);
    const action = await this.prisma.aiAction.create({
      data: {
        userId,
        conversationId,
        actionType,
        title: proposal.title.slice(0, 160),
        summary: proposal.summary?.slice(0, 400) ?? null,
        payload: payload as unknown as Prisma.InputJsonValue,
        payloadHash: AiActionsService.hashPayload(payload),
        safetyFlags: (proposal.safetyFlags?.slice(0, 6) ?? []) as unknown as Prisma.InputJsonValue,
        status: 'AWAITING_CONFIRMATION',
        expiresAt,
      },
    });
    return this.toPublic(action);
  }

  /**
   * Validation + normalisation du payload PAR TYPE (D17.2 §6.2).
   * Retourne null si la proposition est inutilisable — elle est alors
   * silencieusement écartée de la réponse (jamais d'exécution à l'aveugle).
   */
  private sanitizePayload(
    actionType: AiActionType,
    raw: Record<string, unknown>,
  ): Record<string, unknown> | null {
    const str = (v: unknown, max = 200): string | null =>
      typeof v === 'string' && v.trim().length > 0 ? v.trim().slice(0, max) : null;
    const date = (v: unknown): string | null =>
      typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
    const time = (v: unknown): string | null =>
      typeof v === 'string' && /^\d{2}:\d{2}$/.test(v) ? v : null;
    const amount = (v: unknown): number | null => {
      const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v.replace(/\s/g, '')) : NaN;
      return Number.isFinite(n) && n > 0 && n <= 1_000_000_000 ? Math.round(n) : null;
    };

    if (actionType === 'CREATE_TASK_DRAFT') {
      const title = str(raw.title);
      if (!title) return null;
      return {
        title,
        notes: str(raw.notes, 2000),
        dueDate: date(raw.dueDate),
        priority: ['LOW', 'NORMAL', 'HIGH', 'URGENT'].includes(String(raw.priority)) ? String(raw.priority) : 'NORMAL',
        spaceId: str(raw.spaceId, 64),
      };
    }

    if (actionType === 'PROPOSE_EVENT_CHANGE') {
      const eventId = str(raw.eventId, 64);
      if (!eventId) return null;
      const newStartDate = date(raw.newStartDate);
      if (!newStartDate) return null;
      return {
        eventId,
        newStartDate,
        newStartTime: time(raw.newStartTime),
        newEndDate: date(raw.newEndDate) ?? newStartDate,
        newEndTime: time(raw.newEndTime),
        reason: str(raw.reason, 300),
      };
    }

    // PROPOSE_FINANCIAL_CORRECTION
    const kind = String(raw.kind ?? raw.transactionType).toUpperCase();
    if (kind !== 'INCOME' && kind !== 'EXPENSE') return null;
    const amt = amount(raw.amount);
    if (amt === null) return null;
    return {
      kind,
      amount: amt,
      label: str(raw.label, 160) ?? 'Correction proposée par HELM AI',
      accountId: str(raw.accountId, 64),
      categoryId: str(raw.categoryId, 64),
      date: date(raw.date) ?? new Date().toISOString().slice(0, 10),
      note: str(raw.reason, 300) ?? str(raw.note, 300),
    };
  }

  // ─────────────────────── Lecture ───────────────────────

  private toPublic(action: {
    id: string;
    actionType: string;
    status: string;
    title: string;
    summary: string | null;
    payload: unknown;
    payloadHash: string;
    safetyFlags: unknown;
    result: unknown;
    error: unknown;
    expiresAt: Date;
    confirmedAt: Date | null;
    executedAt: Date | null;
    createdAt: Date;
  }) {
    return {
      id: action.id,
      actionType: action.actionType,
      status: action.status,
      title: action.title,
      summary: action.summary,
      payload: action.payload,
      payloadHash: action.payloadHash,
      safetyFlags: action.safetyFlags,
      result: action.result,
      error: action.error,
      expiresAt: action.expiresAt,
      confirmedAt: action.confirmedAt,
      executedAt: action.executedAt,
      createdAt: action.createdAt,
      requiresConfirmation: action.status === 'AWAITING_CONFIRMATION',
    };
  }

  async get(userId: string, id: string, ip?: string) {
    const action = await this.prisma.aiAction.findFirst({ where: { id, userId } });
    if (!action) return null;
    if (action.status === 'AWAITING_CONFIRMATION') {
      await this.expireIfDue(action.id, action.expiresAt, userId);
      if (action.expiresAt.getTime() <= Date.now()) {
        action.status = 'EXPIRED';
      }
    }
    void ip;
    return this.toPublic(action);
  }

  async list(userId: string, statuses?: string[]) {
    const where: Prisma.AiActionWhereInput = { userId };
    if (statuses && statuses.length > 0) where.status = { in: statuses.slice(0, 6) };
    const actions = await this.prisma.aiAction.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 30,
    });
    return actions
      .map((a) => {
        if (a.status === 'AWAITING_CONFIRMATION' && this.expireIfDueSync(a.expiresAt)) {
          return { ...a, status: 'EXPIRED' };
        }
        return a;
      })
      .map((a) => this.toPublic(a));
  }

  private expireIfDueSync(expiresAt: Date): boolean {
    return expiresAt.getTime() <= Date.now();
  }

  // ─────────────────────── Confirmation (le cœur) ───────────────────────

  /**
   * POST /ai/actions/:id/confirm — confirme puis exécute.
   * dto.payloadHash : hash tel que présenté à l'utilisateur (protection STALE).
   * dto.idempotencyKey : UUID généré par le client POUR CETTE tentative.
   */
  async confirm(
    userId: string,
    id: string,
    dto: { payloadHash: string; idempotencyKey: string },
    ip?: string,
  ) {
    // 1) Idempotence — la réponse est rejouée à l'identique sur rejeu.
    const requestHash = AiActionsService.hashPayload({ actionId: id, payloadHash: dto.payloadHash });
    const existing = await this.prisma.aiIdempotencyRecord.findUnique({
      where: { idempotencyKey: dto.idempotencyKey },
    });
    if (existing) {
      if (existing.userId !== userId || existing.requestHash !== requestHash) {
        throw new AiActionError('AI_ACTION_ALREADY_PROCESSED');
      }
      return existing.response as Record<string, unknown>;
    }

    const started = Date.now();
    const action = await this.prisma.aiAction.findFirst({ where: { id, userId } });
    if (!action) return null;

    // 2) Machine à états — un seul chemin vers l'exécution.
    switch (action.status) {
      case 'SUCCEEDED':
      case 'EXECUTING':
      case 'REVALIDATING':
        throw new AiActionError('AI_ACTION_ALREADY_PROCESSED', `statut ${action.status}`);
      case 'CANCELLED':
      case 'REJECTED':
      case 'FAILED':
        throw new AiActionError('AI_ACTION_REJECTED', `statut ${action.status}`);
      case 'EXPIRED':
        throw new AiActionError('AI_ACTION_EXPIRED');
      case 'AWAITING_CONFIRMATION':
      case 'PROPOSED':
        break; // chemin nominal
      default:
        throw new AiActionError('AI_ACTION_REJECTED', `statut inconnu ${action.status}`);
    }

    // 3) Fenêtre de confirmation bornée.
    if (await this.expireIfDue(action.id, action.expiresAt, userId)) {
      throw new AiActionError('AI_ACTION_EXPIRED');
    }

    // 4) Le hash présenté à l'utilisateur doit être EXACTEMENT celui proposé.
    if (!/^[a-f0-9]{64}$/i.test(dto.payloadHash) || dto.payloadHash.toLowerCase() !== action.payloadHash) {
      throw new AiActionError('AI_ACTION_STALE', 'le payload affiché diffère du payload enregistré');
    }

    // 5) Exécution transactionnelle : verrou d'état → revalidation → écriture.
    //    La transaction RETOURNE un verdict au lieu de lancer — un throw
    //    interne annulerait aussi l'écriture du statut FAILED et de l'audit
    //    (rollback global), laissant l'action en AWAITING_CONFIRMATION.
    //    (Wrapper objet : le narrowing TS ne traverse pas les closures.)
    const outcome: { error: AiActionError | null } = { error: null };
    const result = await this.prisma.$transaction(
      async (tx) => {
        // Verrou optimiste : on ne s'exécute que depuis AWAITING_CONFIRMATION.
        const locked = await tx.aiAction.updateMany({
          where: { id: action.id, status: 'AWAITING_CONFIRMATION' },
          data: { status: 'EXECUTING', confirmedAt: new Date() },
        });
        if (locked.count !== 1) {
          outcome.error = new AiActionError('AI_ACTION_ALREADY_PROCESSED', 'confirmations concurrentes');
          return null;
        }

        try {
          const exec = await this.execute(tx, userId, action.actionType as AiActionType, action.payload as Record<string, unknown>);

          const updated = await tx.aiAction.update({
            where: { id: action.id },
            data: {
              status: 'SUCCEEDED',
              executedAt: new Date(),
              result: exec as unknown as Prisma.InputJsonValue,
            },
          });

          await tx.aiToolExecution.create({
            data: {
              actionId: action.id,
              userId,
              toolName: this.toolNameFor(action.actionType),
              direction: 'WRITE_DRAFT',
              arguments: { id: action.id } as unknown as Prisma.InputJsonValue,
              result: { ok: true } as unknown as Prisma.InputJsonValue,
              status: 'SUCCEEDED',
              durationMs: Date.now() - started,
            },
          });
          await tx.aiAuditEvent.create({
            data: {
              userId,
              action: 'ACTION_CONFIRMED',
              entity: action.id,
              details: { actionType: action.actionType } as unknown as Prisma.InputJsonValue,
              ip: ip ?? null,
            },
          });
          await tx.aiUsageRecord.create({
            data: { userId, kind: 'ACTION_CONFIRM', latencyMs: Date.now() - started },
          });

          return this.toPublic(updated);
        } catch (e) {
          // Échec d'exécution : FAILED + piste d'audit — COMMITTÉS (pas de
          // throw interne), puis l'erreur est relancée après la transaction.
          const code = e instanceof AiActionError ? e.aiCode : 'AI_TOOL_VALIDATION_FAILED';
          const message = e instanceof Error ? e.message : 'Exécution impossible.';
          await tx.aiAction.update({
            where: { id: action.id },
            data: {
              status: 'FAILED',
              error: { code, message } as unknown as Prisma.InputJsonValue,
              executedAt: new Date(),
            },
          });
          await tx.aiToolExecution.create({
            data: {
              actionId: action.id,
              userId,
              toolName: this.toolNameFor(action.actionType),
              direction: 'WRITE_DRAFT',
              status: 'FAILED',
              errorCode: code,
              durationMs: Date.now() - started,
            },
          });
          await tx.aiAuditEvent.create({
            data: {
              userId,
              action: 'ACTION_FAILED',
              entity: action.id,
              details: { code } as unknown as Prisma.InputJsonValue,
              ip: ip ?? null,
            },
          });
          outcome.error = e instanceof AiActionError ? e : new AiActionError('AI_TOOL_VALIDATION_FAILED', message);
          return null;
        }
      },
      { timeout: 15_000 },
    );

    if (outcome.error) {
      // Mémorisation idempotente de l'échec (double-tap = même erreur).
      const txError: AiActionError = outcome.error;
      await this.prisma.aiIdempotencyRecord
        .create({
          data: {
            userId,
            idempotencyKey: dto.idempotencyKey,
            requestHash,
            endpoint: `/ai/actions/${id}/confirm`,
            response: {
              statusCode: txError.getStatus(),
              code: txError.aiCode,
              message: (txError.getResponse() as { message: string }).message,
            } as unknown as Prisma.InputJsonValue,
            statusCode: txError.getStatus(),
            expiresAt: new Date(Date.now() + IDEMPOTENCY_TTL_HOURS * 3_600_000),
          },
        })
        .catch(() => undefined);
      throw txError;
    }

    if (result === null) {
      // Cas théorique (verrou concurrent sans erreur positionnée).
      throw new AiActionError('AI_ACTION_ALREADY_PROCESSED', 'confirmations concurrentes');
    }

    // 6) Mémorisation idempotente (après commit — sinon la réponse
    //    cachée pourrait décrire une exécution qui a échoué).
    await this.prisma.aiIdempotencyRecord.create({
      data: {
        userId,
        idempotencyKey: dto.idempotencyKey,
        requestHash,
        endpoint: `/ai/actions/${id}/confirm`,
        response: result as unknown as Prisma.InputJsonValue,
        statusCode: 200,
        expiresAt: new Date(Date.now() + IDEMPOTENCY_TTL_HOURS * 3_600_000),
      },
    });

    return result;
  }

  /** POST /ai/actions/:id/cancel — refus utilisateur. */
  async cancel(userId: string, id: string, reason?: string, ip?: string) {
    const action = await this.prisma.aiAction.findFirst({ where: { id, userId } });
    if (!action) return null;
    if (action.status !== 'AWAITING_CONFIRMATION' && action.status !== 'PROPOSED') {
      throw new AiActionError('AI_ACTION_ALREADY_PROCESSED', `statut ${action.status}`);
    }
    await this.prisma.aiAction.update({
      where: { id },
      data: { status: 'CANCELLED' },
    });
    await this.audit(userId, 'ACTION_CANCELLED', id, reason ? { reason: reason.slice(0, 200) } : undefined, ip);
    return { cancelled: true, id };
  }

  // ─────────────────────── Exécutions (brouillons via Resource) ───────────────────────

  private toolNameFor(actionType: string): string {
    switch (actionType) {
      case 'CREATE_TASK_DRAFT':
        return 'create_task_draft';
      case 'PROPOSE_EVENT_CHANGE':
        return 'propose_event_change';
      case 'PROPOSE_FINANCIAL_CORRECTION':
        return 'propose_financial_correction';
      default:
        return actionType.toLowerCase();
    }
  }

  /** Première espace de vie de l'utilisateur (cible par défaut des drafts). */
  private async defaultSpaceId(userId: string, explicit?: string | null): Promise<string> {
    if (explicit) {
      const space = await this.prisma.resource.findFirst({
        where: { id: explicit, ownerId: userId, type: 'Space', deletedAt: null },
        select: { id: true },
      });
      if (space) return space.id;
    }
    const space = await this.prisma.resource.findFirst({
      where: { ownerId: userId, type: 'Space', deletedAt: null },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    if (!space) {
      throw new AiActionError('AI_TOOL_VALIDATION_FAILED', "Aucun espace de vie n'est encore synchronisé.");
    }
    return space.id;
  }

  private async execute(
    tx: Prisma.TransactionClient,
    userId: string,
    actionType: AiActionType,
    payload: Record<string, unknown>,
  ): Promise<{ resourceId: string; serverVersion: number; kind: string }> {
    const now = new Date();

    if (actionType === 'CREATE_TASK_DRAFT') {
      const spaceId = await this.defaultSpaceId(userId, payload.spaceId as string | undefined);
      const resourceId = randomUUID();
      const data = {
        id: resourceId,
        spaceId,
        listId: null,
        parentId: null,
        title: String(payload.title),
        notes: (payload.notes as string | null) ?? null,
        status: 'TODO',
        priority: payload.priority ?? 'NORMAL',
        startDate: null,
        dueDate: payload.dueDate ?? null,
        reminderMinutes: null,
        estimatedMinutes: null,
        progressPercent: null,
        recurrenceRuleId: null,
        position: 0,
        completedAt: null,
        archivedAt: null,
        createdAt: now.toISOString(),
        updatedAt: now.toISOString(),
      };
      await tx.resource.create({
        data: {
          id: resourceId,
          ownerId: userId,
          type: 'Task',
          data: data as unknown as Prisma.InputJsonValue,
          version: 1,
          deviceId: AI_DEVICE,
        },
      });
      await tx.syncChange.create({
        data: { resourceId, ownerId: userId, type: 'Task', op: 'CREATE', deviceId: AI_DEVICE },
      });
      return { resourceId, serverVersion: 1, kind: 'Task' };
    }

    if (actionType === 'PROPOSE_EVENT_CHANGE') {
      // Revalidation : l'événement doit exister ET appartenir à l'utilisateur.
      const event = await tx.resource.findFirst({
        where: { id: String(payload.eventId), ownerId: userId, type: 'CalendarEvent', deletedAt: null },
      });
      if (!event || !event.data) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', "L'événement visé n'existe plus.");
      }
      const data = { ...(event.data as Record<string, unknown>) };
      const oldStart = data.startDate as string | undefined;
      data.startDate = payload.newStartDate;
      data.startTime = payload.newStartTime ?? null;
      data.endDate = payload.newEndDate ?? payload.newStartDate;
      data.endTime = payload.newEndTime ?? null;
      data.status = 'RESCHEDULED';
      data.originalStart = data.originalStart ?? oldStart ?? null;
      data.updatedAt = now.toISOString();
      const version = event.version + 1;
      await tx.resource.update({
        where: { id: event.id },
        data: {
          data: data as unknown as Prisma.InputJsonValue,
          version,
          deviceId: AI_DEVICE,
          updatedAt: now,
        },
      });
      await tx.syncChange.create({
        data: { resourceId: event.id, ownerId: userId, type: 'CalendarEvent', op: 'UPDATE', deviceId: AI_DEVICE },
      });
      return { resourceId: event.id, serverVersion: version, kind: 'CalendarEvent' };
    }

    // PROPOSE_FINANCIAL_CORRECTION — transaction de régularisation.
    let accountId = (payload.accountId as string | undefined) ?? null;
    if (!accountId) {
      const account = await tx.resource.findFirst({
        where: { ownerId: userId, type: 'FinancialAccount', deletedAt: null },
        orderBy: { createdAt: 'asc' },
        select: { id: true },
      });
      if (!account) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'Aucun compte financier synchronisé.');
      }
      accountId = account.id;
    } else {
      const account = await tx.resource.findFirst({
        where: { id: accountId, ownerId: userId, type: 'FinancialAccount', deletedAt: null },
        select: { id: true },
      });
      if (!account) {
        throw new AiActionError('AI_TOOL_VALIDATION_FAILED', 'Le compte visé n\'existe plus.');
      }
    }
    const accountResource = await tx.resource.findUnique({ where: { id: accountId } });
    const spaceId = await this.defaultSpaceId(
      userId,
      (accountResource?.data as Record<string, unknown> | null)?.spaceId as string | undefined,
    );
    const resourceId = randomUUID();
    const occurredAt = new Date(`${String(payload.date)}T12:00:00.000Z`);
    const data = {
      id: resourceId,
      spaceId,
      accountId,
      kind: String(payload.kind),
      amount: payload.amount,
      currency: 'XOF',
      loanId: null,
      status: 'POSTED',
      categoryId: payload.categoryId ?? null,
      transferId: null,
      rateToXof: null,
      occurredAt: (Number.isNaN(occurredAt.getTime()) ? now : occurredAt).toISOString(),
      note: `${String(payload.label)}${payload.note ? ` — ${String(payload.note)}` : ''} (HELM AI)`,
      createdAt: now.toISOString(),
    };
    await tx.resource.create({
      data: {
        id: resourceId,
        ownerId: userId,
        type: 'FinancialTransaction',
        data: data as unknown as Prisma.InputJsonValue,
        version: 1,
        deviceId: AI_DEVICE,
      },
    });
    await tx.syncChange.create({
      data: { resourceId, ownerId: userId, type: 'FinancialTransaction', op: 'CREATE', deviceId: AI_DEVICE },
    });
    return { resourceId, serverVersion: 1, kind: 'FinancialTransaction' };
  }

  /** Purge des enregistrements idempotents expirés (appelé au fil de l'eau). */
  async sweepIdempotency() {
    const res = await this.prisma.aiIdempotencyRecord.deleteMany({
      where: { expiresAt: { lt: new Date() } },
    });
    return res.count;
  }
}
