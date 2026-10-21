import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { NvidiaProvider } from './nvidia.provider';
import { AiActionsService } from './ai-actions.service';
import { AiPreferencesService } from './ai-preferences.service';

/**
 * HELM AI (Dossier 17) — Phase 2 : actions confirmées + idempotence,
 * préférences (Policy Engine), usage & quotas, audit minimisé.
 * Phase 1 conservée : assistant conversationnel, données limitées par
 * défaut, réponses structurées sourcées, aucune mutation sans confirmation.
 */
@Module({
  controllers: [AiController],
  providers: [AiService, NvidiaProvider, AiActionsService, AiPreferencesService],
})
export class AiModule {}
