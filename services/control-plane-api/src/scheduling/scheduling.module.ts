import { Module } from '@nestjs/common';
import { ScheduleModule } from '@nestjs/schedule';
import { ResourceCollectionScheduler } from './resource-collection.scheduler';

@Module({
  imports: [ScheduleModule.forRoot()],
  providers: [ResourceCollectionScheduler],
})
export class SchedulingModule {}
