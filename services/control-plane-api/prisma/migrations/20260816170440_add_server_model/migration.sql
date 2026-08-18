-- CreateTable
CREATE TABLE "Server" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "instanceId" TEXT NOT NULL,
    "pterodactylId" INTEGER NOT NULL,
    "pterodactylUuid" TEXT NOT NULL,
    "identifier" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "nodeId" INTEGER NOT NULL,
    "lastSyncedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Server_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Server_tenantId_idx" ON "Server"("tenantId");

-- CreateIndex
CREATE INDEX "Server_instanceId_idx" ON "Server"("instanceId");

-- CreateIndex
CREATE UNIQUE INDEX "Server_instanceId_pterodactylUuid_key" ON "Server"("instanceId", "pterodactylUuid");

-- AddForeignKey
ALTER TABLE "Server" ADD CONSTRAINT "Server_instanceId_fkey" FOREIGN KEY ("instanceId") REFERENCES "PterodactylInstance"("id") ON DELETE CASCADE ON UPDATE CASCADE;
