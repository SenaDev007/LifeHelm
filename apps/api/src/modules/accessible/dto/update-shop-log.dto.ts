import { IsNumber, IsOptional, IsString } from "class-validator";

export class UpdateShopLogDto {
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

