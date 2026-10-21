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
  Req,
  UseGuards,
} from '@nestjs/common';
import { Request } from 'express';
import { Throttle, ThrottleGuard } from '../common/throttle.guard';
import { JwtAuthGuard } from '../common/jwt-auth.guard';
import { CurrentUser, AccessTokenPayload } from '../common/current-user.decorator';
import { AiService } from './ai.service';
import { NvidiaProviderError } from './nvidia.provider';
import { CreateConversationDto, SendMessageDto } from './dto/ai.dto';

/**
 * API HELM AI — Dossier 17.4 §4 (préfixe global /api/v1).
 * Authentification JWT obligatoire ; les identifiants d'URL ne sont jamais
 * des preuves d'autorisation (vérification du propriétaire à chaque route).
 */
@Controller('ai')
@UseGuards(ThrottleGuard, JwtAuthGuard)
export class AiController {
  constructor(private readonly ai: AiService) {}

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
}
