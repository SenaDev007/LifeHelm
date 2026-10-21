import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Patch,
  Post,
  Put,
  Query,
  Req,
  UseGuards,
  ValidationPipe,
} from '@nestjs/common';
import { Request } from 'express';
import { Throttle, ThrottleGuard } from '../common/throttle.guard';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser, AccessTokenPayload } from '../common/current-user.decorator';
import { AiService } from './ai.service';
import { AiActionsService } from './ai-actions.service';
import { AiPreferencesService } from './ai-preferences.service';
import { AiConsentsService } from './ai-consents.service';
import { AiInsightsService } from './ai-insights.service';
import { NvidiaProviderError } from './nvidia.provider';
import {
  CancelActionDto,
  ConfirmActionDto,
  CreateConversationDto,
  SendMessageDto,
  SetConsentDto,
  UpdatePreferencesDto,
} from './dto/ai.dto';

/**
 * API HELM AI — Dossiers 17.2 / 17.4 / 17.6 (préfixe global /api/v1).
 * Authentification JWT obligatoire ; les identifiants d'URL ne sont jamais
 * des preuves d'autorisation (vérification du propriétaire à chaque route).
 * NB : JwtAuthGuard AVANT ThrottleGuard → quota par utilisateur (pas par IP).
 */
@Controller('ai')
@UseGuards(JwtAuthGuard, ThrottleGuard)
export class AiController {
  constructor(
    private readonly ai: AiService,
    private readonly actions: AiActionsService,
    private readonly prefs: AiPreferencesService,
    private readonly consents: AiConsentsService,
    private readonly insights: AiInsightsService,
  ) {}

  /** Disponibilité de l'assistant (AVAILABLE / OFFLINE — D17.3 §17.4). */
  @Get('status')
  status() {
    return this.ai.status();
  }

  @Post('conversations')
  @HttpCode(201)
  @Throttle(20, 60_000)
  create(@CurrentUser() user: AccessTokenPayload, @Body() dto: CreateConversationDto) {
    return this.ai.createConversation(user.sub, dto.entryPoint ?? 'CENTRAL_ASSISTANT', dto.moduleContext);
  }

  @Get('conversations')
  async list(@CurrentUser() user: AccessTokenPayload) {
    const conversations = await this.ai.listConversations(user.sub);
    return { conversations };
  }

  @Get('conversations/:id')
  async detail(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const conv = await this.ai.getConversation(user.sub, id);
    if (!conv) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Conversation introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return conv;
  }

  @Delete('conversations/:id')
  async remove(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const ok = await this.ai.deleteConversation(user.sub, id);
    if (!ok) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Conversation introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return { deleted: true };
  }

  /**
   * Envoi d'une demande → réponse structurée HELM AI.
   * L'orchestration relit les données métier à la source, appelle le modèle
   * et valide le contrat de réponse (D17.4 §4.2).
   */
  @Post('conversations/:id/messages')
  @Throttle(12, 60_000)
  async send(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id') id: string,
    @Body() dto: SendMessageDto,
    @Req() _req: Request,
  ) {
    try {
      const result = await this.ai.sendMessage(user.sub, id, dto.message);
      if (result === null) {
        throw new HttpException(
          { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Conversation introuvable.' },
          HttpStatus.NOT_FOUND,
        );
      }
      return result;
    } catch (e) {
      if (e instanceof NvidiaProviderError) {
        const status = e.code === 'AI_RATE_LIMITED' ? HttpStatus.TOO_MANY_REQUESTS : HttpStatus.SERVICE_UNAVAILABLE;
        throw new HttpException(
          { statusCode: status, code: e.code, message: e.message, retryable: e.code === 'AI_RATE_LIMITED' },
          status,
        );
      }
      throw e;
    }
  }

  // ─────────────────────── Actions confirmées (D17.2 §6) ───────────────────────

  /** Détail d'une action — expiration paresseuse incluse. */
  @Get('actions/:id')
  async getAction(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const action = await this.actions.get(user.sub, id);
    if (!action) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Action introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return action;
  }

  /** Historique des actions (filtre par statut : ?status=AWAITING_CONFIRMATION,SUCCEEDED). */
  @Get('actions')
  async listActions(
    @CurrentUser() user: AccessTokenPayload,
    @Query('status') status?: string,
  ) {
    const statuses = status?.split(',').map((s) => s.trim().toUpperCase()).filter(Boolean);
    const actions = await this.actions.list(user.sub, statuses);
    return { actions };
  }

  /**
   * Confirmation + exécution. Le client DOIT renvoyer le payloadHash tel
   * qu'affiché (preuve de lecture) et une clé d'idempotence UUID par
   * tentative (double-tap et rejeu réseau protégés).
   */
  @Post('actions/:id/confirm')
  @HttpCode(200)
  @Throttle(30, 60_000)
  async confirmAction(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id') id: string,
    @Body(new ValidationPipe({ transform: true })) dto: ConfirmActionDto,
    @Req() req: Request,
  ) {
    const result = await this.actions.confirm(user.sub, id, dto, req.ip);
    if (result === null) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Action introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return result;
  }

  /** Refus utilisateur — l'action passe en CANCELLED (traçable). */
  @Post('actions/:id/cancel')
  @HttpCode(200)
  @Throttle(30, 60_000)
  async cancelAction(
    @CurrentUser() user: AccessTokenPayload,
    @Param('id') id: string,
    @Body() dto: CancelActionDto,
    @Req() req: Request,
  ) {
    const result = await this.actions.cancel(user.sub, id, dto.reason, req.ip);
    if (result === null) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Action introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return result;
  }

  // ─────────────────────── Préférences (D17.2 §7.2) ───────────────────────

  @Get('preferences')
  async getPreferences(@CurrentUser() user: AccessTokenPayload) {
    return this.prefs.get(user.sub);
  }

  @Patch('preferences')
  @Throttle(20, 60_000)
  async updatePreferences(
    @CurrentUser() user: AccessTokenPayload,
    @Body() dto: UpdatePreferencesDto,
    @Req() req: Request,
  ) {
    return this.prefs.update(user.sub, dto, req.ip);
  }

  // ─────────────────────── Usage & quotas (D17.2 §7.5) ───────────────────────

  @Get('usage')
  async usage(@CurrentUser() user: AccessTokenPayload) {
    return this.prefs.usage(user.sub);
  }

  // ─────────────── Briefing quotidien (D17.6 — Phase 3) ───────────────

  /**
   * Briefing du jour (sections structurées + accroche + alertes du jour).
   * Cache par date : généré une fois, renvoyé tel quel ensuite.
   */
  @Get('briefing')
  @Throttle(10, 60_000)
  briefing(@CurrentUser() user: AccessTokenPayload, @Query('date') date?: string) {
    return this.insights.getOrGenerate(user.sub, date, 'ON_DEMAND');
  }

  // ─────────────── Alertes intelligentes (D17.6 — Phase 3) ───────────────

  /** Liste des alertes (filtre ?status=UNREAD|READ|DISMISSED). */
  @Get('alerts')
  @Throttle(20, 60_000)
  alerts(@CurrentUser() user: AccessTokenPayload, @Query('status') status?: string) {
    return this.insights.listAlerts(user.sub, status);
  }

  /** Marquer comme lue (idempotent). */
  @Post('alerts/:id/read')
  @HttpCode(200)
  @Throttle(30, 60_000)
  async readAlert(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const alert = await this.insights.markRead(user.sub, id);
    if (!alert) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Alerte introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return alert;
  }

  /** Ignorer l'alerte (pas de recréation pour la même période). */
  @Post('alerts/:id/dismiss')
  @HttpCode(200)
  @Throttle(30, 60_000)
  async dismissAlert(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const alert = await this.insights.dismiss(user.sub, id);
    if (!alert) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Alerte introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return alert;
  }

  // ─────────────── Consentements granulaires (D17.6 — Phase 3) ───────────────

  /** Catalogue des périmètres sensibles + état courant. */
  @Get('consents')
  async listConsents(@CurrentUser() user: AccessTokenPayload) {
    return this.consents.list(user.sub);
  }

  /** Octroi / retrait explicite d'un consentement — journalisé. */
  @Put('consents/:scope')
  @Throttle(15, 60_000)
  setConsent(
    @CurrentUser() user: AccessTokenPayload,
    @Param('scope') scope: string,
    @Body(new ValidationPipe({ transform: true })) dto: SetConsentDto,
    @Req() req: Request,
  ) {
    return this.consents.set(user.sub, scope, dto.granted, req.ip);
  }
}
