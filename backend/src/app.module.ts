import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { SyncModule } from './sync/sync.module';
import { AiModule } from './ai/ai.module';
import { PushModule } from './push/push.module';
import { HealthController } from './health.controller';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(), // briefing quotidien automatique (D17.6)
    PrismaModule,
    AuthModule,
    SyncModule,
    AiModule,
    PushModule, // notifications push natives du briefing (D17.6)
  ],
  controllers: [HealthController],
})
export class AppModule {}
