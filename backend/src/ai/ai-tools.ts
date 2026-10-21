import { PrismaService } from '../prisma/prisma.service';

/**
 * Outils métier HELM AI — LECTURE SEULE (D17 §4, D17.4 §5).
 * Règles :
 * - Chaque outil filtre STRICTEMENT par ownerId (isolation des comptes).
 * - Les données proviennent des Resource synchronisées (source de vérité) —
 *   HELM AI ne recalcule pas une « deuxième vérité » : elle agrège ce que
 *   les modules ont enregistré.
 * - Minimisation : top N, fenêtres bornées, aucun dump de base.
 * - Les contenus (notes, messages) sont traités comme DONNÉES non fiables,
 *   jamais comme des instructions (résistance à l'injection, D17.2 §8.3).
 */

export interface ToolContext {
  userId: string;
  asOf: Date;
}

const XOF = 'FCFA';

function num(v: unknown): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : 0;
}

function str(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/** Date Drift sérialisée en ISO (string) — tolère aussi epoch ms (number). */
function asDate(v: unknown): Date | null {
  if (typeof v === 'string') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === 'number') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function inWindow(d: Date | null, from: Date, to: Date): boolean {
  return d !== null && d >= from && d <= to;
}

export class AiTools {
  constructor(private readonly prisma: PrismaService) {}

  /** Charge les ressources d'un type pour l'utilisateur (non supprimées). */
  private async resources(userId: string, types: string[], limit = 400) {
    return this.prisma.resource.findMany({
      where: { ownerId: userId, type: { in: types }, deletedAt: null },
      select: { type: true, data: true, updatedAt: true },
      take: limit,
      orderBy: { updatedAt: 'desc' },
    });
  }

  /** D17 §3.1 — synthèse financière du mois (recettes, dépenses, solde). */
  async getFinanceSummary(ctx: ToolContext) {
    const now = ctx.asOf;
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

    const [txs, cats, accounts] = await Promise.all([
      this.resources(ctx.userId, ['FinancialTransaction'], 600),
      this.resources(ctx.userId, ['FinancialCategory'], 300),
      this.resources(ctx.userId, ['FinancialAccount'], 50),
    ]);
    const catName = new Map<string, string>();
    for (const c of cats) {
      const d = c.data as Record<string, unknown> | null;
      const id = str(d?.id);
      if (id) catName.set(id, str(d?.name) ?? 'Catégorie');
    }

    let income = 0;
    let expense = 0;
    const byCategory = new Map<string, number>();
    for (const t of txs) {
      const d = t.data as Record<string, unknown> | null;
      if (!d) continue;
      if (str(d.status) === 'REVERSED' || str(d.status) === 'VOIDED') continue;
      const occurred = asDate(d.occurredAt);
      if (!inWindow(occurred, monthStart, monthEnd)) continue;
      const amount = num(d.amount);
      const currency = str(d.currency) ?? 'XOF';
      if (currency !== 'XOF') continue; // jamais d'addition sans conversion documentée (D05)
      const kind = str(d.kind);
      if (kind === 'INCOME') income += amount;
      else if (kind === 'EXPENSE') {
        expense += amount;
        const label = catName.get(str(d.categoryId) ?? '') ?? 'Non catégorisé';
        byCategory.set(label, (byCategory.get(label) ?? 0) + amount);
      }
    }

    const topCategories = [...byCategory.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([name, total]) => ({ name, total }));

    // Comptes (ids exposés pour cibler une correction financière).
    const accountList = accounts
      .map((a) => {
        const d = (a.data as Record<string, unknown> | null) ?? {};
        return { id: str(d.id) ?? '', name: str(d.name) ?? 'Compte', type: str(d.type) ?? 'CASH' };
      })
      .filter((a) => a.id !== '')
      .slice(0, 6);

    return {
      period: { from: monthStart.toISOString().slice(0, 10), to: monthEnd.toISOString().slice(0, 10) },
      currency: XOF,
      income,
      expense,
      balance: income - expense,
      topExpenseCategories: topCategories,
      accounts: accountList,
      accountsCount: accounts.length,
      transactionsCounted: txs.length,
      asOf: ctx.asOf.toISOString(),
    };
  }

  /** D17 §3.1 — état des budgets de la période (prévu vs consommé). */
  async getBudgetStatus(ctx: ToolContext) {
    const now = ctx.asOf;
    const [budgets, txs, cats, adjustments, carryovers] = await Promise.all([
      this.resources(ctx.userId, ['Budget'], 100),
      this.resources(ctx.userId, ['FinancialTransaction'], 600),
      this.resources(ctx.userId, ['FinancialCategory'], 300),
      this.resources(ctx.userId, ['BudgetAdjustment'], 200),
      this.resources(ctx.userId, ['BudgetCarryover'], 200),
    ]);

    const catName = new Map<string, string>();
    for (const c of cats) {
      const d = c.data as Record<string, unknown> | null;
      const id = str(d?.id);
      if (id) catName.set(id, str(d?.name) ?? 'Catégorie');
    }

    const today = now.toISOString().slice(0, 10);
    return budgets
      .map((b) => {
        const d = (b.data as Record<string, unknown> | null) ?? {};
        const start = str(d.periodStart) ?? '';
        const end = str(d.periodEnd) ?? '';
        if (!start || !end || start > today || end < today) return null;

        const budgetId = str(d.id) ?? '';
        let planned = num(d.initialAmount);
        for (const a of adjustments) {
          const ad = a.data as Record<string, unknown> | null;
          if (str(ad?.budgetId) === budgetId) planned += num(ad?.amount);
        }
        for (const c of carryovers) {
          const cd = c.data as Record<string, unknown> | null;
          if (str(cd?.budgetId) === budgetId) planned += num(cd?.amount);
        }

        // Consommé : dépenses XOF comptabilisées sur la période du budget
        // (affectation par catégorie du budget lorsque disponible).
        const budgetCat = str(d.categoryId);
        let spent = 0;
        for (const t of txs) {
          const td = t.data as Record<string, unknown> | null;
          if (!td || str(td.kind) !== 'EXPENSE') continue;
          if (str(td.status) === 'REVERSED' || str(td.status) === 'VOIDED') continue;
          if ((str(td.currency) ?? 'XOF') !== 'XOF') continue;
          const occurred = asDate(td.occurredAt);
          if (!occurred) continue;
          const day = occurred.toISOString().slice(0, 10);
          if (day < start || day > end) continue;
          if (budgetCat && str(td.categoryId) !== budgetCat) continue;
          spent += num(td.amount);
        }

        const consumedPercent = planned > 0 ? Math.round((spent / planned) * 100) : null;
        return {
          name: str(d.name) ?? 'Budget',
          category: budgetCat ? catName.get(budgetCat) ?? null : null,
          period: `${start} → ${end}`,
          planned,
          spent,
          remaining: planned - spent,
          consumedPercent,
          nearThreshold: consumedPercent !== null && consumedPercent >= 80,
          currency: XOF,
        };
      })
      .filter((b): b is NonNullable<typeof b> => b !== null)
      .slice(0, 12);
  }

  /** D17 §3.1 — échéances à venir (ne diminuent pas le solde, D05 §10.6).
   *  `includeOverdue` (moteur d'alertes) : inclut aussi les échéances
   *  ouvertes dont la date est dépassée (jusqu'à 60 jours en arrière). */
  async getUpcomingDueItems(ctx: ToolContext, days = 30, includeOverdue = false) {
    const items = await this.resources(ctx.userId, ['FinancialDueItem'], 200);
    const from = includeOverdue
      ? new Date(ctx.asOf.getTime() - 60 * 86_400_000)
      : ctx.asOf;
    const to = new Date(ctx.asOf.getTime() + days * 86_400_000);
    return items
      .map((i) => {
        const d = (i.data as Record<string, unknown> | null) ?? {};
        if (str(d.status) !== 'OPEN') return null;
        const due = str(d.dueDate);
        if (!due || due < from.toISOString().slice(0, 10) || due > to.toISOString().slice(0, 10)) return null;
        return {
          label: str(d.label) ?? 'Échéance',
          expectedAmount: num(d.expectedAmount),
          currency: str(d.currency) === 'XOF' ? XOF : str(d.currency) ?? XOF,
          dueDate: due,
          overdue: includeOverdue && due < ctx.asOf.toISOString().slice(0, 10),
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .sort((a, b) => a.dueDate.localeCompare(b.dueDate))
      .slice(0, 10);
  }

  /** D17 §3.2 — priorités de tâches (échéances, priorités, blocages). */
  async getTaskPriorities(ctx: ToolContext, limit = 10) {
    const [tasks, deps] = await Promise.all([
      this.resources(ctx.userId, ['Task'], 400),
      this.resources(ctx.userId, ['TaskDependency'], 300),
    ]);
    const blockedBy = new Map<string, string[]>();
    for (const d of deps) {
      const dd = d.data as Record<string, unknown> | null;
      const task = str(dd?.taskId);
      const dependsOn = str(dd?.dependsOn);
      if (task && dependsOn) blockedBy.set(task, [...(blockedBy.get(task) ?? []), dependsOn]);
    }
    const taskTitle = new Map<string, string>();
    for (const t of tasks) {
      const d = t.data as Record<string, unknown> | null;
      const id = str(d?.id);
      if (id) taskTitle.set(id, str(d?.title) ?? 'Tâche');
    }

    const prioRank: Record<string, number> = { URGENT: 0, HIGH: 1, NORMAL: 2, LOW: 3 };
    const today = ctx.asOf.toISOString().slice(0, 10);
    return tasks
      .map((t) => {
        const d = (t.data as Record<string, unknown> | null) ?? {};
        const status = str(d.status) ?? 'TODO';
        if (status === 'DONE' || status === 'CANCELLED' || status === 'ARCHIVED') return null;
        const due = str(d.dueDate);
        const blocked = (blockedBy.get(str(d.id) ?? '') ?? [])
          .map((id) => taskTitle.get(id) ?? 'tâche')
          .slice(0, 3);
        return {
          title: str(d.title) ?? 'Tâche',
          status,
          priority: str(d.priority) ?? 'NORMAL',
          dueDate: due,
          overdue: due !== null && due < today,
          blockedBy: blocked.length > 0 ? blocked : undefined,
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .sort((a, b) => {
        const pa = prioRank[a.priority] ?? 2;
        const pb = prioRank[b.priority] ?? 2;
        if (pa !== pb) return pa - pb;
        return (a.dueDate ?? '9999').localeCompare(b.dueDate ?? '9999');
      })
      .slice(0, limit);
  }

  /** D17 §3.3 — agenda des prochains jours (le jour même INCLUS). */
  async getUpcomingEvents(ctx: ToolContext, days = 7) {
    const events = await this.resources(ctx.userId, ['CalendarEvent'], 400);
    // Début du jour courant : les événements d'aujourd'hui ne doivent pas être
    // exclus par la comparaison avec l'heure courante (bug Phase 2 corrigé).
    const from = new Date(`${ctx.asOf.toISOString().slice(0, 10)}T00:00:00.000Z`);
    const to = new Date(ctx.asOf.getTime() + days * 86_400_000);
    return events
      .map((e) => {
        const d = (e.data as Record<string, unknown> | null) ?? {};
        if (str(d.status) === 'CANCELLED') return null;
        // La table Drift CalendarEvents porte startDate (date civile) + startTime
        // (« HH:mm ») — pas de champ startAt (bug Phase 1 corrigé).
        const dateStr = str(d.startDate);
        if (!dateStr) return null;
        const day = new Date(`${dateStr}T00:00:00.000Z`);
        if (Number.isNaN(day.getTime()) || day < from || day > to) return null;
        return {
          id: str(d.id) ?? '',
          title: str(d.title) ?? 'Événement',
          startDate: dateStr,
          startTime: str(d.startTime) ?? undefined,
          endDate: str(d.endDate) ?? undefined,
          location: str(d.location) ?? undefined,
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .sort((a, b) => a.startDate.localeCompare(b.startDate))
      .slice(0, 10);
  }

  /** D17 §3.4 — avancement des projets actifs. */
  async getProjectProgress(ctx: ToolContext, limit = 8) {
    const [projects, stages, milestones, tasks] = await Promise.all([
      this.resources(ctx.userId, ['Project'], 100),
      this.resources(ctx.userId, ['ProjectStage'], 300),
      this.resources(ctx.userId, ['ProjectMilestone'], 300),
      this.resources(ctx.userId, ['Task'], 400),
    ]);
    const stageProject = new Map<string, string>();
    for (const s of stages) {
      const d = s.data as Record<string, unknown> | null;
      const id = str(d?.id);
      const p = str(d?.projectId);
      if (id && p) stageProject.set(id, p);
    }
    const msProject = new Map<string, string>();
    for (const m of milestones) {
      const d = m.data as Record<string, unknown> | null;
      const id = str(d?.id);
      const p = str(d?.projectId);
      if (id && p) msProject.set(id, p);
    }

    const stats = new Map<string, { stagesDone: number; stagesTotal: number; msDone: number; msTotal: number; tasksDone: number; tasksTotal: number }>();
    const bump = (pid: string, kind: 'stage' | 'ms' | 'task', done: boolean) => {
      const s = stats.get(pid) ?? { stagesDone: 0, stagesTotal: 0, msDone: 0, msTotal: 0, tasksDone: 0, tasksTotal: 0 };
      if (kind === 'stage') { s.stagesTotal++; if (done) s.stagesDone++; }
      if (kind === 'ms') { s.msTotal++; if (done) s.msDone++; }
      if (kind === 'task') { s.tasksTotal++; if (done) s.tasksDone++; }
      stats.set(pid, s);
    };
    for (const s of stages) {
      const d = s.data as Record<string, unknown> | null;
      const pid = stageProject.get(str(d?.id) ?? '');
      if (pid) bump(pid, 'stage', str(d?.status) === 'DONE');
    }
    for (const m of milestones) {
      const d = m.data as Record<string, unknown> | null;
      const pid = msProject.get(str(d?.id) ?? '');
      if (pid) bump(pid, 'ms', str(d?.status) === 'DONE');
    }
    for (const t of tasks) {
      const d = t.data as Record<string, unknown> | null;
      const pid = str(d?.projectId);
      if (pid) bump(pid, 'task', str(d?.status) === 'DONE');
    }

    return projects
      .map((p) => {
        const d = (p.data as Record<string, unknown> | null) ?? {};
        const status = str(d.status) ?? 'ACTIVE';
        if (status === 'ARCHIVED' || status === 'CANCELLED') return null;
        const id = str(d.id) ?? '';
        const s = stats.get(id) ?? { stagesDone: 0, stagesTotal: 0, msDone: 0, msTotal: 0, tasksDone: 0, tasksTotal: 0 };
        const manual = num(d.progressPercent);
        const computed = s.tasksTotal > 0
          ? Math.round((s.tasksDone / s.tasksTotal) * 100)
          : s.stagesTotal > 0
            ? Math.round((s.stagesDone / s.stagesTotal) * 100)
            : null;
        return {
          name: str(d.name) ?? 'Projet',
          status,
          dueDate: str(d.endDate) ?? str(d.targetDate),
          tasksDone: s.tasksDone,
          tasksTotal: s.tasksTotal,
          milestonesDone: s.msDone,
          milestonesTotal: s.msTotal,
          progressPercent: manual > 0 ? { value: manual, kind: 'MANUAL' } : computed !== null ? { value: computed, kind: 'CALCULATED' } : null,
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .slice(0, limit);
  }

  /**
   * D17 §3.6 — recherche dans les contenus autorisés (titres et notes,
   * correspondance simple). Les contenus trouvés restent des DONNÉES.
   */
  async searchAuthorizedContent(ctx: ToolContext, query: string, limit = 8) {
    const q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    const types = ['Note', 'Task', 'Project', 'Contact', 'FinancialDueItem'];
    const rows = await this.resources(ctx.userId, types, 400);
    const results: Array<{ module: string; title: string; snippet: string }> = [];
    for (const r of rows) {
      const d = (r.data as Record<string, unknown> | null) ?? {};
      const title = str(d.title) ?? str(d.name) ?? str(d.label) ?? null;
      const body = str(d.content) ?? str(d.note) ?? '';
      const haystack = `${title ?? ''} ${body}`.toLowerCase();
      if (!haystack.includes(q)) continue;
      const idx = haystack.indexOf(q);
      const snippet = body.slice(Math.max(0, idx - 40), idx + 80).replace(/\s+/g, ' ').trim();
      results.push({
        module: r.type,
        title: title ?? '(sans titre)',
        snippet: snippet.length > 0 ? snippet : '(titre correspondant)',
      });
      if (results.length >= limit) break;
    }
    return results;
  }

  // ─────────────── Phase 3 (D17.6) : périmètres sensibles à consentement ───────────────

  /**
   * D17.6 — Tendances bien-être (consentement wellbeing.journal requis).
   * Scores moyens et tendance sur 14 jours — JAMAIS le texte des notes
   * (minimisation : chiffres uniquement).
   */
  async getWellbeingSummary(ctx: ToolContext) {
    const rows = await this.resources(ctx.userId, ['WellbeingEntry'], 200);
    const since = new Date(ctx.asOf.getTime() - 14 * 86_400_000);
    const sinceKey = since.toISOString().slice(0, 10);
    const entries = rows
      .map((r) => (r.data as Record<string, unknown> | null) ?? {})
      .filter((d) => {
        const dateKey = str(d.dateKey);
        return dateKey !== null && dateKey >= sinceKey;
      })
      .sort((a, b) => (str(b.dateKey) ?? '').localeCompare(str(a.dateKey) ?? ''));
    if (entries.length === 0) {
      return { window: '14 jours', entriesCount: 0, note: 'Aucun enregistrement sur la période.' };
    }
    const avg = (key: string): number | null => {
      const vals = entries.map((e) => num(e[key])).filter((v) => v > 0);
      return vals.length === 0 ? null : Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 10) / 10;
    };
    // Tendance : moyenne des 3 derniers jours vs les précédents.
    const trend = (key: string): 'up' | 'down' | 'stable' | null => {
      const vals = entries.map((e) => num(e[key])).filter((v) => v > 0);
      if (vals.length < 5) return null;
      const recent = vals.slice(0, 3);
      const older = vals.slice(3);
      const rAvg = recent.reduce((a, b) => a + b, 0) / recent.length;
      const oAvg = older.reduce((a, b) => a + b, 0) / older.length;
      if (Math.abs(rAvg - oAvg) < 0.4) return 'stable';
      return rAvg > oAvg ? 'up' : 'down';
    };
    return {
      window: '14 jours',
      entriesCount: entries.length,
      moodAverage: avg('mood'), // 1..5 — subjectif, jamais un diagnostic
      energyAverage: avg('energy'),
      stressAverage: avg('stress'),
      moodTrend: trend('mood'),
      stressTrend: trend('stress'),
      lastEntryDate: str(entries[0].dateKey),
      asOf: ctx.asOf.toISOString(),
    };
  }

  /**
   * D17.6 — Activité messagerie (consentement messaging.read requis).
   * Comptages uniquement — JAMAIS le contenu des messages.
   */
  async getMessagingSummary(ctx: ToolContext) {
    const [messages, conversations] = await Promise.all([
      this.resources(ctx.userId, ['Message'], 400),
      this.resources(ctx.userId, ['Conversation'], 100),
    ]);
    const since = new Date(ctx.asOf.getTime() - 7 * 86_400_000);
    let total = 0;
    let unread = 0;
    let recent = 0;
    const byConversation = new Map<string, number>();
    for (const m of messages) {
      const d = (m.data as Record<string, unknown> | null) ?? {};
      if (str(d.deletedAt)) continue;
      total++;
      const status = str(d.status) ?? 'SENT';
      if (status !== 'READ' && status !== 'FAILED') unread++;
      const sent = asDate(d.sentAt);
      if (sent && sent >= since) recent++;
      const conv = str(d.conversationId);
      if (conv) byConversation.set(conv, (byConversation.get(conv) ?? 0) + 1);
    }
    const topThreads = [...byConversation.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([id, count]) => ({
        id,
        title: conversations.find((c) => str((c.data as Record<string, unknown>)?.id) === id)
          ? str((conversations.find((c) => str((c.data as Record<string, unknown>)?.id) === id)!.data as Record<string, unknown>)?.title) ?? 'Conversation'
          : 'Conversation',
        messages: count,
      }));
    return {
      window: '7 jours',
      conversationsCount: conversations.length,
      messagesTotal: total,
      messagesUnread: unread,
      messagesRecent: recent,
      activeThreads: topThreads,
      asOf: ctx.asOf.toISOString(),
    };
  }

  /**
   * D17.6 — Digest des notes (consentement notes.content requis).
   * Titres + extraits courts des notes récentes (maximisation bornée).
   */
  async getNotesDigest(ctx: ToolContext, limit = 8) {
    const rows = await this.resources(ctx.userId, ['Note'], 200);
    return rows
      .map((r) => {
        const d = (r.data as Record<string, unknown> | null) ?? {};
        if (str(d.trashedAt)) return null;
        const plain = (str(d.plainText) ?? '').replace(/\s+/g, ' ').trim();
        return {
          title: str(d.title) ?? '(sans titre)',
          pinned: d.pinned === true,
          excerpt: plain.slice(0, 120) || '(vide)',
          updatedAt: r.updatedAt.toISOString(),
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
      .slice(0, limit);
  }

  /**
   * D17.6 — Prêts et emprunts actifs (règles d'alertes intelligentes).
   * Utilisé par le moteur d'alertes, pas transmis tel quel au modèle.
   */
  async getActiveLoans(ctx: ToolContext) {
    const rows = await this.resources(ctx.userId, ['Loan'], 100);
    const today = ctx.asOf.toISOString().slice(0, 10);
    return rows
      .map((r) => {
        const d = (r.data as Record<string, unknown> | null) ?? {};
        if (str(d.status) !== 'ACTIVE') return null;
        const expected = str(d.expectedAt);
        return {
          id: str(d.id) ?? '',
          direction: str(d.direction) === 'LENT' ? 'LENT' : 'BORROWED',
          counterparty: str(d.counterparty) ?? '—',
          principalAmount: num(d.principalAmount),
          currency: str(d.currency) === 'XOF' ? XOF : str(d.currency) ?? XOF,
          expectedAt: expected,
          overdue: expected !== null && expected < today,
        };
      })
      .filter((x): x is NonNullable<typeof x> => x !== null);
  }
}
