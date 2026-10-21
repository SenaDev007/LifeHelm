import { IsOptional, IsString, MinLength, MaxLength, IsEmail, Matches, IsNotEmpty, IsArray, ArrayMaxSize, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

/** Inscription — courriel OU téléphone (au moins un des deux), D01.3 §6.3. */
export class RegisterDto {
  @IsOptional()
  @IsEmail({}, { message: 'Adresse courriel invalide.' })
  email?: string;

  @IsOptional()
  @Matches(/^\+?[0-9\s\-().]{6,20}$/, { message: 'Numéro de téléphone invalide.' })
  phone?: string;

  @IsString()
  @MinLength(8, { message: 'Le mot de passe doit contenir au moins 8 caractères.' })
  @MaxLength(72)
  password!: string;

  @IsString()
  @IsNotEmpty({ message: 'Le prénom est requis.' })
  @MaxLength(60)
  firstName!: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  lastName?: string;

  /** Profession libre (référentiel quasi exhaustif côté application). */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  profession?: string;

  /** Code ISO du pays (ex. « BJ »). */
  @IsOptional()
  @IsString()
  @MaxLength(2)
  country?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceName?: string;
}

/** Connexion — identifiant = courriel OU téléphone. */
export class LoginDto {
  @IsString()
  @IsNotEmpty({ message: 'Identifiant requis.' })
  identifier!: string;

  @IsString()
  @IsNotEmpty({ message: 'Mot de passe requis.' })
  password!: string;

  @IsOptional()
  @IsString()
  @MaxLength(6)
  totpCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  deviceName?: string;
}

export class RefreshDto {
  @IsString()
  @IsNotEmpty({ message: 'Jeton de renouvellement requis.' })
  refreshToken!: string;
}

export class LogoutDto {
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}

export class ChangePasswordDto {
  @IsString()
  @IsNotEmpty()
  currentPassword!: string;

  @IsString()
  @MinLength(8, { message: 'Le nouveau mot de passe doit contenir au moins 8 caractères.' })
  newPassword!: string;
}

export class ForgotPasswordDto {
  @IsString()
  @IsNotEmpty({ message: 'Identifiant requis.' })
  identifier!: string;
}

export class ResetPasswordDto {
  @IsString()
  @IsNotEmpty()
  resetToken!: string;

  @IsString()
  @MinLength(8, { message: 'Le mot de passe doit contenir au moins 8 caractères.' })
  newPassword!: string;
}

export class TotpDto {
  @IsString()
  @Matches(/^\d{6}$/, { message: 'Code à 6 chiffres requis.' })
  totpCode!: string;
}

export class VerifyCodeDto {
  @IsString()
  @Matches(/^\d{6}$/, { message: 'Code à 6 chiffres requis.' })
  code!: string;
}

/** Mise à jour du profil (PATCH /auth/profile). */
export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  @MaxLength(60)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  lastName?: string;

  @IsOptional()
  @Matches(/^\+?[0-9\s\-().]{6,20}$/, { message: 'Numéro de téléphone invalide.' })
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  profession?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2)
  country?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  avatarUrl?: string;
}

/** Suppression définitive du compte (DELETE /auth/account). */
export class DeleteAccountDto {
  @IsString()
  @IsNotEmpty({ message: 'Mot de passe requis.' })
  password!: string;
}

/** Question de sécurité (question + réponse hachée sha256 côté client). */
export class SecurityQuestionItem {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  question!: string;

  @IsString()
  @Matches(/^[a-f0-9]{64}$/, { message: 'Réponse hachée sha256 attendue.' })
  answerHash!: string;
}

/** Enregistrement des questions de sécurité (POST /auth/security-questions). */
export class SetSecurityQuestionsDto {
  @IsArray()
  @ArrayMaxSize(3)
  @ValidateNested({ each: true })
  @Type(() => SecurityQuestionItem)
  items!: SecurityQuestionItem[];
}

/** Vérification des réponses → jeton de réinitialisation (POST /auth/recover). */
export class RecoverDto {
  @IsString()
  @IsNotEmpty()
  identifier!: string;

  @IsNotEmpty()
  answers!: Record<string, string>;
}
