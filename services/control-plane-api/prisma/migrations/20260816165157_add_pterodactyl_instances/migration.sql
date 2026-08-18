-- CreateEnum
CREATE TYPE "InstanceStatus" AS ENUM ('PENDING_SYNC', 'ONLINE', 'DEGRADED', 'UNREACHABLE');

-- CreateEnum
CREATE TYPE "CredentialKind" AS ENUM ('APPLICATION_API_KEY', 'CLIENT_API_KEY');

-- CreateTable
CREATE TABLE "PterodactylInstance" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "baseUrl" TEXT NOT NULL,
    "status" "InstanceStatus" NOT NULL DEFAULT 'PENDING_SYNC',
    "panelVersion" TEXT,
    "lastSyncedAt" TIMESTAMP(3),
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PterodactylInstance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "InstanceCredential" (
    "id" TEXT NOT NULL,
    "instanceId" TEXT NOT NULL,
    "kind" "CredentialKind" NOT NULL,
    "ciphertext" BYTEA NOT NULL,
    "keyVersion" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InstanceCredential_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PterodactylInstance_tenantId_idx" ON "PterodactylInstance"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "PterodactylInstance_tenantId_baseUrl_key" ON "PterodactylInstance"("tenantId", "baseUrl");

-- CreateIndex
CREATE UNIQUE INDEX "InstanceCredential_instanceId_kind_key" ON "InstanceCredential"("instanceId", "kind");

-- AddForeignKey
ALTER TABLE "PterodactylInstance" ADD CONSTRAINT "PterodactylInstance_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "InstanceCredential" ADD CONSTRAINT "InstanceCredential_instanceId_fkey" FOREIGN KEY ("instanceId") REFERENCES "PterodactylInstance"("id") ON DELETE CASCADE ON UPDATE CASCADE;
