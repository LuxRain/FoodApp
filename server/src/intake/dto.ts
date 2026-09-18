import { Type } from "class-transformer";
import { IsArray, IsBoolean, IsDateString, IsIn, IsNumber, IsOptional, IsString, IsUUID, Max, Min, ValidateNested } from "class-validator";

export class CreateSessionDto {
  @IsUUID() receivingLocationId!: string;
  @IsDateString() receivedAt!: string;
  @IsOptional() @IsString() sourceChannel?: string;
  @IsString() clientMutationId!: string;
}

export class ProductLookupDto {
  @IsString() rawCode!: string;
  @IsIn(["upc_a", "upc_e", "ean_8", "ean_13", "gtin_14", "gs1", "qr", "code_128", "unknown"]) scheme!: string;
}

class AllergenDto {
  @IsIn(["milk", "egg", "fish", "crustacean_shellfish", "tree_nuts", "peanuts", "wheat", "soybeans", "sesame"]) code!: string;
  @IsIn(["contains", "cross_contact_advisory", "not_declared_on_label", "unknown"]) declaration!: string;
  @IsOptional() @IsString() labelText?: string;
}

export class CreateItemDto {
  @IsOptional() @IsUUID() productId?: string;
  @IsString() productName!: string;
  @IsOptional() @IsString() brand?: string;
  @IsIn(["barcode", "qr", "gs1", "image", "manual"]) identitySource!: string;
  @IsNumber() @Min(0.001) quantity!: number;
  @IsString() quantityUnit!: string;
  @IsString() dateType!: string;
  @IsOptional() @IsDateString() dateValue?: string;
  @IsOptional() @IsString() dateLabelRaw?: string;
  @IsString() storageType!: string;
  @IsUUID() storageLocationId!: string;
  @IsString() packageCondition!: string;
  @IsString() temperatureStatus!: string;
  @IsIn(["recorded", "not_labeled", "not_applicable", "unknown"]) calorieStatus!: string;
  @IsOptional() @IsNumber() @Min(0) calories?: number;
  @IsOptional() @IsString() calorieBasis?: string;
  @IsArray() @ValidateNested({ each: true }) @Type(() => AllergenDto) allergens!: AllergenDto[];
  @IsArray() requiredFieldConfidence!: number[];
}

export class SubmitItemDto {
  @IsDateString() userReviewedAt!: string;
  @IsOptional() @IsBoolean() allergenConflict = false;
  @IsOptional() @IsBoolean() evidenceConflict = false;
  @IsOptional() @IsBoolean() duplicateSuspected = false;
}

export class AdminDecisionDto {
  @IsIn(["accept", "quarantine", "reject"]) decision!: "accept" | "quarantine" | "reject";
  @IsString() reason!: string;
}
