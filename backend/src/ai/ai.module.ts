import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { NvidiaProvider } from './nvidia.provider';
import { AiActionsService } from './ai-actions.service';
import { AiPreferencesService } from './ai-preferences.service';
import { AiConsentsService } from './ai-consents.service';
import { AiInsightsService } from './ai-insights.service';
import { PushModule } from '../push/push.module';

/**
 * HELM AI (Dossier 17) — Phase 3 : briefing quotidien automatique,
 * alertes intelligentes dédupliquées, consentements granulaires.
 * Phase 2 conservée : actions confirmées + idempotence, préférences
 * (Policy Engine × consentements), usage & quotas, audit minimisé.
 * Phase 1 conservée : assistant conversationnel, données limitées par
 * défaut, réponses structurées sourcées, aucune mutation sans confirmation.
 */
@Module({
  imports: [PushModule], // notification push à la génération du briefing (cron)
  controllers: [AiController],
  providers: [
    AiService,
    NvidiaProvider,
    AiActionsService,
    AiPreferencesService,
    AiConsentsService,
    AiInsightsService,
  ],
})
export class AiModule {}
