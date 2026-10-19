import { IsArray, IsIn, IsISO8601, IsObject, IsOptional, IsString, IsUUID, MaxLength, ArrayMaxSize, ArrayMinSize, IsInt, Min, Max } from 'class-validator';

/** Une opération cliente issue de la queue locale persistante (CDC §6.4). */
export class SyncOperationDto {
  @IsUUID('4', { message: 'opId doit être un UUID v4.' })
  opId!: string;

  @IsString()
  @MaxLength(60)
  resourceType!: string; // ex: Task, Note, FinancialTransaction

  @IsString()
  @MaxLength(64)
  resourceId!: string;

  @IsIn(['CREATE', 'UPDATE', 'DELETE'])
  op!: 'CREATE' | 'UPDATE' | 'DELETE';

  @IsISO8601()
  occurredAt!: string; // horodatage de la mutation locale

  /** Snapshot JSON complet de la ligne (format Drift toJson) — requis sauf DELETE. */
  @IsOptional()
  @IsObject()
  data?: Record<string, unknown> | null;
}

export class PushSyncDto {
  @IsString()
  @MaxLength(64)
  deviceId!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100, { message: 'Maximum 100 opérations par lot.' })
  operations!: SyncOperationDto[];
}

export interface SyncResult {
  opId: string;
  status: 'APPLIED' | 'DUPLICATE' | 'CONFLICT' | 'REJECTED';
  serverVersion?: number;
  reason?: string;
}

export interface ChangeEntry {
  seq: number;
  resourceType: string;
  resourceId: string;
  op: 'CREATE' | 'UPDATE' | 'DELETE';
  data: Record<string, unknown> | null;
  deleted: boolean;
  version: number;
  updatedAt: string;
}
