-- CreateTable
CREATE TABLE "ProcessedJob" (
    "id" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "jobType" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "processedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProcessedJob_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ProcessedJob_jobId_key" ON "ProcessedJob"("jobId");

-- CreateIndex
CREATE INDEX "ProcessedJob_tenantId_processedAt_idx" ON "ProcessedJob"("tenantId", "processedAt");
