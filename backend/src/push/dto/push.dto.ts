import { IsIn, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';

export class RegisterDeviceDto {
  /** Jeton FCM de l'appareil (format souple : FCM fait autorité au premier envoi). */
  @IsString()
  @Length(20, 4096)
  @Matches(/^[A-Za-z0-9:_\-]+$/, { message: 'Jeton push invalide.' })
  token!: string;

  @IsIn(['ANDROID', 'IOS', 'WEB'])
  platform!: string;

  /** Identifiant d'appareil local (base Drift) — optionnel. */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  appVersion?: string;
}
