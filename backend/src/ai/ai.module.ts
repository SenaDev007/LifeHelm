import { Module } from '@nestjs/common';
import { AiController } from './ai.controller';
import { AiService } from './ai.service';
import { NvidiaProvider } from './nvidia.provider';

/**
 * HELM AI (Dossier 17) — Phase 1 : assistant conversationnel.
 * Assistant central + accès contextuel, données limitées par défaut,
 * réponses structurées sourcées, aucune mutation sans confirmation.
 */
@Module({
  controllers: [AiController],
  providers: [AiService, NvidiaProvider],
})
export class AiModule {}
