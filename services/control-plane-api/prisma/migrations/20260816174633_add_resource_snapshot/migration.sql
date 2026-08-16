-- CreateTable
CREATE TABLE "ResourceSnapshot" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "serverId" TEXT NOT NULL,
    "observedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "cpuAbsolutePercent" DOUBLE PRECISION,
    "memoryBytes" BIGINT,
    "diskBytes" BIGINT,
    "networkRxBytes" BIGINT,
    "networkTxBytes" BIGINT,
    "uptimeMs" BIGINT,

    CONSTRAINT "ResourceSnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ResourceSnapshot_serverId_observedAt_idx" ON "ResourceSnapshot"("serverId", "observedAt");

-- CreateIndex
CREATE INDEX "ResourceSnapshot_tenantId_observedAt_idx" ON "ResourceSnapshot"("tenantId", "observedAt");

-- AddForeignKey
ALTER TABLE "ResourceSnapshot" ADD CONSTRAINT "ResourceSnapshot_serverId_fkey" FOREIGN KEY ("serverId") REFERENCES "Server"("id") ON DELETE CASCADE ON UPDATE CASCADE;
