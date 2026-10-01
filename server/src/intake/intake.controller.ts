import { Body, Controller, Get, Headers, Param, Post, Query, Res, UploadedFile, UseGuards, UseInterceptors } from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import type { Response } from "express";
import { Actor, RequestActorGuard, Roles, type RequestActor } from "../auth/request-context";
import { DashboardService } from "../dashboard/dashboard.service";
import { EvidenceService } from "../evidence/evidence.service";
import { ProductLookupService } from "../product/product-lookup.service";
import { AdminDecisionDto, CreateItemDto, CreateSessionDto, ProductLookupDto, SubmitItemDto } from "./dto";
import { IntakeService } from "./intake.service";

@Controller("v1")
@UseGuards(RequestActorGuard)
export class IntakeController {
  constructor(private readonly intake: IntakeService, private readonly dashboardService: DashboardService, private readonly productLookup: ProductLookupService, private readonly evidence: EvidenceService) {}

  @Post("product-lookups")
  lookupProduct(@Actor() actor: RequestActor, @Body() body: ProductLookupDto) { return this.productLookup.lookup(actor, body.rawCode, body.scheme); }

  @Post("intake-sessions")
  createSession(@Actor() actor: RequestActor, @Body() body: CreateSessionDto) { return this.intake.createSession(actor, body); }

  @Post("intake-sessions/:sessionId/items")
  createItem(@Actor() actor: RequestActor, @Param("sessionId") sessionId: string, @Body() body: CreateItemDto) { return this.intake.createItem(actor, sessionId, body); }

  @Post("intake-items/:itemId/submit")
  submit(@Actor() actor: RequestActor, @Param("itemId") itemId: string, @Body() body: SubmitItemDto, @Headers("idempotency-key") key: string) { return this.intake.submitItem(actor, itemId, body, key); }

  @Post("intake-items/:itemId/evidence")
  @UseInterceptors(FileInterceptor("photo", { limits: { fileSize: 10 * 1024 * 1024, files: 1 } }))
  uploadEvidence(
    @Actor() actor: RequestActor,
    @Param("itemId") itemId: string,
    @UploadedFile() file: { buffer: Buffer; size: number; mimetype: string } | undefined,
    @Body("capturedAt") capturedAt?: string,
  ) { return this.evidence.upload(actor, itemId, file, capturedAt); }

  @Get("intake-items/:itemId/evidence")
  listEvidence(@Actor() actor: RequestActor, @Param("itemId") itemId: string) { return this.evidence.list(actor, itemId); }

  @Get("intake-items/:itemId/evidence/:evidenceId")
  async readEvidence(@Actor() actor: RequestActor, @Param("itemId") itemId: string, @Param("evidenceId") evidenceId: string, @Res() response: Response) {
    const asset = await this.evidence.read(actor, itemId, evidenceId);
    response.setHeader("Content-Type", asset.contentType);
    response.setHeader("Cache-Control", "private, no-store");
    response.send(asset.data);
  }

  @Get("donation-items")
  dashboard(@Actor() actor: RequestActor, @Query("search") search?: string, @Query("limit") limit?: string) { return this.dashboardService.list(actor, search, Number(limit || 50)); }

  @Get("admin/review-queue")
  @Roles("admin")
  reviewQueue(@Actor() actor: RequestActor) { return this.intake.reviewQueue(actor); }

  @Post("admin/intake-items/:itemId/decision")
  @Roles("admin")
  decide(@Actor() actor: RequestActor, @Param("itemId") itemId: string, @Body() body: AdminDecisionDto, @Headers("idempotency-key") key: string) { return this.intake.decide(actor, itemId, body, key); }
}
