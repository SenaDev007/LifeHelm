import { IsEmail, IsEnum, IsOptional, IsString, MinLength } from "class-validator";
import { AppLanguage, Currency, Plan, UIMode } from "@prisma/client";

export class RegisterDto {
  @IsString()
  name!: string;

  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(6)
  password!: string;

  @IsOptional()
  @IsEnum(Currency)
  currency?: Currency;

  @IsOptional()
  @IsEnum(AppLanguage)
  language?: AppLanguage;

  @IsOptional()
  @IsEnum(UIMode)
  uiMode?: UIMode;

  @IsOptional()
  @IsEnum(Plan)
  plan?: Plan;
}

