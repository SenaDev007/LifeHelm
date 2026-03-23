import { IsDateString, IsNumber, IsOptional, IsString } from "class-validator";

export class CreateShopLogDto {
  @IsDateString()
  date!: string; // YYYY-MM-DD

  @IsOptional()
  @IsNumber()
  capitalMatin?: number;

  @IsOptional()
  @IsNumber()
  recettes?: number;

  @IsOptional()
  @IsNumber()
  reapprovisionnement?: number;

  @IsOptional()
  @IsString()
  note?: string;
}

