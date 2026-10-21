import { IsIn, IsOptional, IsString, Length, MaxLength } from 'class-validator';

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
