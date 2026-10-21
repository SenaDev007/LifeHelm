import { Module } from '@nestjs/common';
import { PushController } from './push.controller';
import { PushService } from './push.service';

/**
 * Notifications push natives (D17.6) — appareils enregistrés + envoi FCM v1.
 * Exporté vers AiModule : le cron du briefing notifie les appareils actifs
 * dès que le briefing du jour est généré (mode honnête sans credentials).
 */
@Module({
  controllers: [PushController],
  providers: [PushService],
  exports: [PushService],
})
export class PushModule {}
