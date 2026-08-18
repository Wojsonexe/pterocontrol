-- CreateTable
CREATE TABLE "ServerDatabaseCredential" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "serverId" TEXT NOT NULL,
    "pterodactylDatabaseId" TEXT NOT NULL,
    "host" TEXT NOT NULL,
    "port" INTEGER NOT NULL,
    "databaseName" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "ciphertext" BYTEA NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ServerDatabaseCredential_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ServerDatabaseCredential_tenantId_idx" ON "ServerDatabaseCredential"("tenantId");

-- CreateIndex
CREATE UNIQUE INDEX "ServerDatabaseCredential_serverId_pterodactylDatabaseId_key" ON "ServerDatabaseCredential"("serverId", "pterodactylDatabaseId");

-- AddForeignKey
ALTER TABLE "ServerDatabaseCredential" ADD CONSTRAINT "ServerDatabaseCredential_serverId_fkey" FOREIGN KEY ("serverId") REFERENCES "Server"("id") ON DELETE CASCADE ON UPDATE CASCADE;
