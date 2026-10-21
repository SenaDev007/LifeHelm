import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpException,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { ThrottleGuard } from '../common/throttle.guard';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser, AccessTokenPayload } from '../common/current-user.decorator';
import { PushService } from './push.service';
import { RegisterDeviceDto } from './dto/push.dto';

/**
 * API Notifications push (D17.6 — préfixe global /api/v1).
 *
 * L'enregistrement d'un appareil est un consentement explicite : l'app ne
 * l'envoie que si l'utilisateur a activé les notifications du briefing dans
 * les préférences HELM AI. Sans credentials Firebase côté serveur, chaque
 * route répond honnêtement (mode DEGRADED) — jamais d'erreur silencieuse.
 */
@Controller('push')
@UseGuards(JwtAuthGuard, ThrottleGuard)
export class PushController {
  constructor(private readonly push: PushService) {}

  /** Disponibilité du push (READY / DEGRADED) et nombre d'appareils actifs. */
  @Get('status')
  status(@CurrentUser() user: AccessTokenPayload) {
    return this.push.status(user.sub);
  }

  /** Enregistre (ou rafraîchit) l'appareil courant — upsert par jeton. */
  @Post('devices')
  @HttpCode(201)
  register(@CurrentUser() user: AccessTokenPayload, @Body() dto: RegisterDeviceDto) {
    return this.push.registerDevice(user.sub, dto);
  }

  /** Appareils enregistrés (jetons masqués). */
  @Get('devices')
  async list(@CurrentUser() user: AccessTokenPayload) {
    const devices = await this.push.listDevices(user.sub);
    return { devices };
  }

  @Delete('devices/:id')
  async remove(@CurrentUser() user: AccessTokenPayload, @Param('id') id: string) {
    const res = await this.push.removeDevice(user.sub, id);
    if (!res) {
      throw new HttpException(
        { statusCode: HttpStatus.NOT_FOUND, code: 'NOT_FOUND', message: 'Appareil introuvable.' },
        HttpStatus.NOT_FOUND,
      );
    }
    return res;
  }

  /**
   * Notification de test — vérifie la chaîne complète (appareils + FCM).
   * Réponses honnêtes : 503 PUSH_NOT_CONFIGURED sans credentials,
   * 409 PUSH_NO_DEVICE sans appareil enregistré.
   */
  @Post('test')
  @HttpCode(200)
  async test(@CurrentUser() user: AccessTokenPayload) {
    const status = await this.push.status(user.sub);
    if (!status.configured) {
      throw new HttpException(
        {
          statusCode: HttpStatus.SERVICE_UNAVAILABLE,
          code: 'PUSH_NOT_CONFIGURED',
          message:
            'Le push n\'est pas configuré sur le serveur (credentials Firebase absents). ' +
            'Les notifications locales de l\'application restent actives.',
        },
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    if (status.activeDevices === 0) {
      throw new HttpException(
        {
          statusCode: HttpStatus.CONFLICT,
          code: 'PUSH_NO_DEVICE',
          message: 'Aucun appareil enregistré pour ce compte.',
        },
        HttpStatus.CONFLICT,
      );
    }
    const report = await this.push.sendToUser(user.sub, {
      title: 'LifeHelm — Notification de test',
      body: 'La chaîne push fonctionne : vos notifications du briefing arriveront ici.',
      data: { route: 'briefing', test: '1' },
    });
    return { ...report, testedAt: new Date().toISOString() };
  }
}
