import { Injectable, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SyncOperationDto, SyncResult, ChangeEntry } from './dto/sync.dto';

/**
 * Types synchronisables (allowlist stricte — miroir des resourceType journalisés
 * par le client Flutter via logOp). Tout type inconnu est rejeté explicitement.
 */
export const SYNCABLE_TYPES: ReadonlySet<string> = new Set([
  // D01 Fondations
  'Space', 'SpaceMember', 'RecurrenceRule',
  // D03 Tâches
  'TaskList', 'Task', 'TaskDependency',
  // D04 Agenda
  'Calendar', 'CalendarEvent', 'EventException',
  // D05 Finances — jamais écrasées silencieusement (CDC §6.4)
  'FinancialAccount', 'FinancialCategory', 'FinancialTransaction', 'Transfer',
  'TransactionAllocation', 'Budget', 'BudgetAdjustment', 'BudgetCarryover',
  'FinancialDueItem', 'AccountReconciliation', 'Loan',
  // D06 Notes & documents
  'Folder', 'Note', 'NoteVersion', 'Document', 'AttachmentLink',
  // D07 Projets & objectifs
  'Project', 'ProjectMember', 'ProjectStage', 'ProjectMilestone', 'ProjectTaskLink',
  'Goal', 'GoalMetric', 'GoalProgressEntry', 'GoalProjectLink',
  // D08 Habitudes & routines
  'Habit', 'HabitSchedule', 'HabitOccurrence', 'Routine', 'RoutineStep', 'RoutineOccurrence',
  // D09 Bien-être (sensible)
  'WellbeingEntry', 'DailyReview', 'ReflectionQuestion',
  // D10 Carrière
  'CareerProfile', 'Skill', 'UserSkill', 'LearningPath', 'LearningPathStep',
  'ProfessionalExperience', 'Certification', 'PortfolioItem',
  // D11 Contacts
  'Contact', 'ContactPoint', 'ContactInteraction', 'ContactLink',
  // D12 Messagerie
  'Conversation', 'ConversationMember', 'Message', 'MessageReaction',
]);

/**
 * Ressources SENSIBLES : divergence multi-appareils ⇒ CONFLICT explicite,
 * jamais d'écrasement silencieux (CDC §6.4 : « les transactions financières
 * ne sont ni dupliquées ni écrasées silencieusement » ; idem notes).
 * Les autres types appliquent un last-arrival-wins documenté (ordre de la
 * queue = chronologie des mutations).
 */
const SENSITIVE_TYPES: ReadonlySet<string> = new Set([
  'FinancialTransaction', 'Transfer', 'TransactionAllocation', 'BudgetAdjustment',
  'BudgetCarryover', 'AccountReconciliation', 'FinancialDueItem',
  'Note', 'NoteVersion', 'Document',
]);

/** Comparaison JSON canonique (clés triées récursivement). */
function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value) ?? 'null';
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${stableStringify(obj[k])}`).join(',')}}`;
}

@Injectable()
export class SyncService {
  private readonly logger = new Logger('SyncService');

  constructor(private prisma: PrismaService) {}

  // ─────────────────────── PUSH : POST /sync/operations ───────────────────────

  async applyOperations(userId: string, deviceId: string, operations: SyncOperationDto[]): Promise<{ results: SyncResult[]; serverSeq: number }> {
    const results: SyncResult[] = [];
    for (const operation of operations) {
      results.push(await this.applyOne(userId, deviceId, operation));
    }
    const serverSeq = await this.currentSeq(userId);
    return { results, serverSeq };
  }

  private async applyOne(userId: string, deviceId: string, op: SyncOperationDto): Promise<SyncResult> {
    // 1) Idempotence par opId (CDC §6.4) — un renvoi renvoie le verdict initial
    const existing = await this.prisma.appliedOp.findUnique({ where: { opId: op.opId } });
    if (existing) {
      return { opId: op.opId, status: 'DUPLICATE', serverVersion: existing.serverVersion ?? undefined };
    }

    // 2) Validation
    if (!SYNCABLE_TYPES.has(op.resourceType)) {
      return { opId: op.opId, status: 'REJECTED', reason: 'Type de ressource inconnu.' };
    }
    if (op.op !== 'DELETE' && (!op.data || typeof op.data !== 'object')) {
      return { opId: op.opId, status: 'REJECTED', reason: 'Données manquantes pour CREATE/UPDATE.' };
    }

    const occurredAt = new Date(op.occurredAt);
    if (Number.isNaN(occurredAt.getTime())) {
      return { opId: op.opId, status: 'REJECTED', reason: 'Horodatage invalide.' };
    }

    // 3) Conflit explicite (ressources sensibles)
    const resource = await this.prisma.resource.findUnique({ where: { id: op.resourceId } });
    if (
      resource &&
      resource.ownerId === userId &&
      op.op !== 'DELETE' &&
      SENSITIVE_TYPES.has(op.resourceType) &&
      resource.deviceId !== null &&
      resource.deviceId !== deviceId &&
      resource.updatedAt > occurredAt &&
      stableStringify(resource.data) !== stableStringify(op.data)
    ) {
      return {
        opId: op.opId,
        status: 'CONFLICT',
        serverVersion: resource.version,
        reason: 'Divergence serveur — résolution explicite requise.',
      };
    }
    // Ressource d'un autre utilisateur avec le même id (collision improbable) → rejet
    if (resource && resource.ownerId !== userId) {
      return { opId: op.opId, status: 'REJECTED', reason: 'Ressource déjà attribuée.' };
    }

    // 4) Application atomique : Resource + SyncChange + AppliedOp
    try {
      const result = await this.prisma.$transaction(async (tx) => {
        let version: number;
        if (op.op === 'DELETE') {
          if (resource) {
            version = resource.version + 1;
            await tx.resource.update({
              where: { id: op.resourceId },
              data: { deletedAt: new Date(), version, deviceId, updatedAt: new Date() },
            });
          } else {
            version = 1;
            await tx.resource.create({
              data: {
                id: op.resourceId, ownerId: userId, type: op.resourceType,
                data: (op.data ?? Prisma.JsonNull) as unknown as Prisma.InputJsonValue,
                version, deletedAt: new Date(), deviceId,
              },
            });
          }
        } else if (resource) {
          version = resource.version + 1;
          await tx.resource.update({
            where: { id: op.resourceId },
            data: {
              data: op.data as Prisma.InputJsonValue,
              version,
              deletedAt: null,
              deviceId,
              updatedAt: new Date(),
            },
          });
        } else {
          version = 1;
          await tx.resource.create({
            data: {
              id: op.resourceId, ownerId: userId, type: op.resourceType,
              data: op.data as Prisma.InputJsonValue,
              version, deviceId,
            },
          });
        }

        await tx.syncChange.create({
          data: {
            resourceId: op.resourceId, ownerId: userId, type: op.resourceType,
            op: op.op, deviceId,
          },
        });
        await tx.appliedOp.create({
          data: { opId: op.opId, userId, deviceId, status: 'APPLIED', serverVersion: version },
        });
        return version;
      });
      return { opId: op.opId, status: 'APPLIED', serverVersion: result };
    } catch (error) {
      // Conflit d'unicité opId (course concurrente) ⇒ DUPLICATE
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        return { opId: op.opId, status: 'DUPLICATE' };
      }
      this.logger.error(`Échec application ${op.opId}: ${String(error)}`);
      return { opId: op.opId, status: 'REJECTED', reason: 'Erreur serveur pendant l’application.' };
    }
  }

  // ─────────────────────── PULL : GET /sync/changes ───────────────────────

  async getChanges(userId: string, cursor: number, limit: number): Promise<{ changes: ChangeEntry[]; nextCursor: number; hasMore: boolean }> {
    const take = Math.min(Math.max(limit, 1), 500);

    const scanned = await this.prisma.syncChange.findMany({
      where: { ownerId: userId, seq: { gt: BigInt(cursor) } },
      orderBy: { seq: 'asc' },
      take: take + 1, // 1 de plus pour savoir s'il reste des données
      include: { resource: true },
    });

    const hasMore = scanned.length > take;
    const window = scanned.slice(0, take);
    if (window.length === 0) {
      return { changes: [], nextCursor: cursor, hasMore };
    }

    // Déduplication : une seule entrée par ressource (la plus récente de la fenêtre)
    const byResource = new Map<string, ChangeEntry>();
    for (const change of window) {
      const r = change.resource;
      byResource.set(change.resourceId, {
        seq: Number(change.seq),
        resourceType: change.type,
        resourceId: change.resourceId,
        op: change.op as ChangeEntry['op'],
        data: (r.data ?? null) as Record<string, unknown> | null,
        deleted: r.deletedAt !== null,
        version: r.version,
        updatedAt: r.updatedAt.toISOString(),
      });
    }

    const nextCursor = Number(window[window.length - 1].seq);
    return { changes: [...byResource.values()], nextCursor, hasMore };
  }

  // ─────────────────────── Statut ───────────────────────

  async getStatus(userId: string) {
    const [seqAgg, resourceCount, lastChange] = await Promise.all([
      this.prisma.syncChange.aggregate({ where: { ownerId: userId }, _max: { seq: true } }),
      this.prisma.resource.count({ where: { ownerId: userId, deletedAt: null } }),
      this.prisma.syncChange.findFirst({ where: { ownerId: userId }, orderBy: { seq: 'desc' } }),
    ]);
    return {
      serverSeq: seqAgg._max.seq ? Number(seqAgg._max.seq) : 0,
      resourceCount,
      lastChangeAt: lastChange?.createdAt.toISOString() ?? null,
    };
  }

  private async currentSeq(userId: string): Promise<number> {
    const agg = await this.prisma.syncChange.aggregate({ where: { ownerId: userId }, _max: { seq: true } });
    return agg._max.seq ? Number(agg._max.seq) : 0;
  }

  /** Nettoyage : ops appliquées de plus de 90 jours (rétention). */
  async purgeOldAppliedOps(): Promise<number> {
    const cutoff = new Date(Date.now() - 90 * 24 * 3600 * 1000);
    const res = await this.prisma.appliedOp.deleteMany({ where: { createdAt: { lt: cutoff } } });
    return res.count;
  }

  /** Exposé pour le smoke test. */
  isSensitive(type: string): boolean {
    return SENSITIVE_TYPES.has(type);
  }

  isSyncable(type: string): boolean {
    return SYNCABLE_TYPES.has(type);
  }
}
