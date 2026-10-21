import { IsBoolean, IsIn, IsInt, IsOptional, IsString, Length, Matches, Max, MaxLength, Min } from 'class-validator';

export class CreateConversationDto {
  @IsOptional()
  @IsIn(['CENTRAL_ASSISTANT', 'MODULE_CONTEXTUAL', 'DAILY_BRIEFING'])
  entryPoint?: string;

  /** Module d'origine (accès contextuel). Information d'affichage uniquement. */
  @IsOptional()
  @IsString()
  @MaxLength(60)
  moduleContext?: string;
}

export class SendMessageDto {
  @IsString()
  @Length(1, 2000)
  message!: string;
}

/** Confirmation d'action (D17.2 §6.3) — le hash EST la preuve que
 *  l'utilisateur a vu exactement ce qui sera exécuté. */
export class ConfirmActionDto {
  @IsString()
  @Matches(/^[a-f0-9]{64}$/i, { message: 'payloadHash doit être un sha256 hexadécimal.' })
  payloadHash!: string;

  /** UUID d'intempotence généré par le client POUR CETTE tentative. */
  @IsString()
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, {
    message: 'idempotencyKey doit être un UUID.',
  })
  idempotencyKey!: string;
}

export class CancelActionDto {
  @IsOptional()
  @IsString()
  @MaxLength(200)
  reason?: string;
}

export class UpdatePreferencesDto {
  @IsOptional()
  @IsIn(['SUGGEST', 'PREPARE', 'ASSIST'])
  autonomyLevel?: string;

  @IsOptional()
  @IsIn(['INFORMATION', 'NORMAL', 'IMPORTANT'])
  alertThreshold?: string;

  /** Périmètre de contexte — modules transmissibles au modèle. */
  @IsOptional()
  contextScope?: Record<string, boolean>;

  @IsOptional()
  @IsBoolean()
  dailyBriefing?: boolean;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(23)
  briefingHour?: number;

  @IsOptional()
  @IsString()
  @MaxLength(8)
  language?: string;
}

/** Consentement granulaire (D17.6) — octroi/retrait explicite d'un périmètre
 *  sensible ; chaque changement est journalisé côté serveur. */
export class SetConsentDto {
  @IsBoolean()
  granted!: boolean;
}
