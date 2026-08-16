-- CreateEnum
CREATE TYPE "AlertMetric" AS ENUM ('CPU_PERCENT', 'MEMORY_BYTES', 'DISK_BYTES', 'SERVER_OFFLINE', 'INSTANCE_OFFLINE');

-- CreateEnum
CREATE TYPE "AlertOperator" AS ENUM ('GREATER_THAN', 'LESS_THAN');

-- CreateTable
CREATE TABLE "AlertRule" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "metric" "AlertMetric" NOT NULL,
    "operator" "AlertOperator",
    "threshold" DOUBLE PRECISION,
    "serverId" TEXT,
    "instanceId" TEXT,
    "cooldownSeconds" INTEGER NOT NULL DEFAULT 300,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AlertRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Alert" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "ruleId" TEXT NOT NULL,
    "resourceId" TEXT NOT NULL,
    "triggeredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMP(3),
    "payload" JSONB NOT NULL,

    CONSTRAINT "Alert_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AlertRule_tenantId_idx" ON "AlertRule"("tenantId");

-- CreateIndex
CREATE INDEX "Alert_tenantId_triggeredAt_idx" ON "Alert"("tenantId", "triggeredAt");

-- CreateIndex
CREATE INDEX "Alert_ruleId_resourceId_idx" ON "Alert"("ruleId", "resourceId");

-- AddForeignKey
ALTER TABLE "Alert" ADD CONSTRAINT "Alert_ruleId_fkey" FOREIGN KEY ("ruleId") REFERENCES "AlertRule"("id") ON DELETE CASCADE ON UPDATE CASCADE;
