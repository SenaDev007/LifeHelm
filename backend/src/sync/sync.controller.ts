import { Body, Controller, Get, HttpCode, Post, Query, UseGuards } from '@nestjs/common';
import { Throttle, ThrottleGuard } from '../common/throttle.guard';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser, AccessTokenPayload } from '../common/current-user.decorator';
import { SyncService } from './sync.service';
import { PushSyncDto } from './dto/sync.dto';

@Controller('sync')
@UseGuards(JwtAuthGuard, ThrottleGuard)
export class SyncController {
  constructor(private sync: SyncService) {}

  /**
   * PUSH — applique un lot d'opérations de la queue locale.
   * Idempotent par opId ; conflits explicites sur les types sensibles.
   */
  @Post('operations')
  @Throttle(60, 60_000)
  @HttpCode(200)
  push(@CurrentUser() user: AccessTokenPayload, @Body() dto: PushSyncDto) {
    return this.sync.applyOperations(user.sub, dto.deviceId, dto.operations);
  }

  /**
   * PULL — modifications depuis le curseur (multi-appareils).
   * GET /sync/changes?cursor=0&limit=200
   */
  @Get('changes')
  @Throttle(120, 60_000)
  pull(
    @CurrentUser() user: AccessTokenPayload,
    @Query('cursor') cursor: string = '0',
    @Query('limit') limit: string = '200',
  ) {
    const c = Math.max(0, Math.floor(Number(cursor) || 0));
    const l = Math.min(500, Math.max(1, Math.floor(Number(limit) || 200)));
    return this.sync.getChanges(user.sub, c, l);
  }

  /** État de synchronisation du compte (diagnostics, écran Synchronisation). */
  @Get('status')
  status(@CurrentUser() user: AccessTokenPayload) {
    return this.sync.getStatus(user.sub);
  }
}
