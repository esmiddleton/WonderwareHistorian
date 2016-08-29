/*


!!! This script makes UNSUPPORTED modifications to your Runtime database !!!
!!!                       USE AT YOUR OWN RISK                           !!!


License
-------
This script can be used without additional charge with any licensed Wonderware Historian server. 
The terms of use are defined in your existing End User License Agreement for the 
Wonderware Historian software.

Modified: 	29-Aug-2016
By:			E. Middleton

*/


-- The stored procedure below will create synch queue entries for ALL configured replication for the specified time period
-- on the indicated Replication Server. This has the effect of "back replicating" one day at a time, starting with the most
-- recent time and moving backwards. This stored procedure is a long-running one that incorporates significant wait time
-- for the Historian Replication processing to complete before adding more backfill items. It tracks/reports
-- progress using entries in the "Annotation" table for the "SysReplicationSyncQueueItemsN" tag, where "N" is the key of
-- the Replication Server.
--
/*
exec wwkbBackfillReplication '2015-12-04 00:00', '2015-12-17 00:00:00', 3

exec wwkbBackfillReplication '2016-07-01 00:00', '2016-07-21 0:00:00', 2

exec wwkbBackfillReplication '2016-07-27 00:00', '2016-07-28 0:00:00', 2
exec wwkbBackfillReplication '2016-08-01 00:00', '2016-08-02 0:00:00', 2
select * from ReplicationSyncRequestInfo where ReplicationServerKey=2   order by earliestexecutiondatetimeUtc desc
update ReplicationSyncRequestInfo set earliestexecutiondatetimeUtc=getutcdate() where ModEndDateTimeUtc < dateadd(minute,-5,getutcdate())
update ReplicationSyncRequestInfo set earliestexecutiondatetimeUtc=getutcdate(), RequestVersion=0 where ReplicationServerKey=2
delete ReplicationSyncRequest where ModEndDateTimeUtc<'2016-01-01'
select * from ReplicationServer
select * from Annotation where Content like (select '%'+ReplicationServerName+'%' from ReplicationServer where ReplicationServerKey=3)
*/
use Runtime
exec aaUserDetailUpdate
go

if not exists (select * from sys.objects where object_id = OBJECT_ID(N'[dbo].[wwkbBackfillReplication]') and type in (N'P', N'PC'))
	begin
		exec dbo.sp_executesql @statement = N'create procedure [dbo].[wwkbBackfillReplication] as' 
	end
go
alter procedure wwkbBackfillReplication (
	@OldestTimeLocal datetime, -- The oldest time for which to backfill, expressed in server local time
	@NewestTimeLocal datetime, -- The newest time for which to backfill, expressed in server local time
	@ReplicationKey int -- The key from the "ReplicationServer" table
 )
as
begin
	set nocount on
	if @NewestTimeLocal > getdate()
		set @NewestTimeLocal = getdate()

	declare @WaitTime nvarchar(10)
	declare @MaxWaitCount int
	declare @MaxQueueReady int

	set @WaitTime='00:01:00' -- 1-minute wait between checking the queue level
	set @MaxWaitCount=240 -- Wait this many times for the queue to be cleared before timing out

	-- The current size of the replication synch queue
	declare @QueueSize int
	set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
	set @MaxQueueReady= @QueueSize + 250 -- Queue is ready for more when it has no more than this many entries

	-- A template to use for entries made to the "Annotation" table to track status
	declare @InvocationId nvarchar(50)
	select @InvocationId=convert(nvarchar(30),getdate(),120) + ' for ''' + ReplicationServerName + '''' from ReplicationServer where ReplicationServerKey=@ReplicationKey

	-- Keep track of when we started executing, so we an estimate when we'll finish
	declare @ExecutionStartUtc datetime
	set @ExecutionStartUtc = GETUTCDATE() 

	-- The start/end times for the next set of replication queue entries (normally 24-hours at a time)
	declare @CurrentStartLocal datetime
	declare @CurrentEndLocal datetime
	declare @NextEndLocal datetime
	declare @CurrentStartUtc datetime
	declare @CurrentEndUtc datetime

	set @NextEndLocal=@NewestTimeLocal

	select top 1 @CurrentStartUtc=dateadd(minute,-TimeZoneOffset,FromDate), 
	@CurrentEndUtc=case when ToDate > getdate() then getdate() else dateadd(minute,-TimeZoneOffset,ToDate) end, 
	@NextEndLocal=FromDate, --dateadd(millisecond,-1,FromDate),
	@CurrentStartLocal=FromDate,
	@CurrentEndLocal=ToDate
	from HistoryBlock
	where datediff(minute,FromDate,@NextEndLocal) > 0
	order by datediff(minute,FromDate,@NextEndLocal) asc, datediff(hour, FromDate, ToDate) desc

	-- Track how many times we've checked on the progress
	declare @WaitCount int

	-- Flag to indicate the entire backfill has completed (or timed out)
	declare @AllDone bit
	set @AllDone=0

	-- Find how many tags are configured to replicate
	declare @EntityCount int
	set @EntityCount = (select count(*) from ReplicationTagEntity where ReplicationServerKey=@ReplicationKey)

	-- Prepare for reporting progress through an annotation on a system tag
	declare @RepTag nvarchar(50)
	declare @RepComment nvarchar(1000)
	set @RepTag = 'SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5))

	-- Record start of execution in the "Annotation" table
	set @RepComment = ' Beginning backfill for ' + convert(nvarchar(10),@EntityCount) + ' tags from ''' + convert(nvarchar(30),@OldestTimeLocal,120)+''' to '''+ convert(nvarchar(30),@NewestTimeLocal,120)+''''
	print convert(nvarchar(50),getdate(),120) + @RepComment
	set @RepComment = @InvocationId + @RepComment
	exec aaAnnotationInsert @RepTag, null, null, null, @RepComment

	-- Variables for calculating progress & estimating completion time
	declare @PercentComplete float
	declare @MinutesRemaining float
	declare @MinutesElapsed float
	declare @MinutesCovered float
	declare @MinutesTotal float
	set @MinutesTotal = datediff(minute,@OldestTimeLocal,@NewestTimeLocal)

	while (@AllDone = 0)
		begin
			-- Make sure it doesn't go too far back
			if @CurrentStartLocal < @OldestTimeLocal
				set @CurrentStartLocal = @OldestTimeLocal

			-- Add sync queue entries
			insert into ReplicationSyncRequest ([ReplicationTagEntityKey] ,[RequestVersion] ,[ModStartDateTimeUtc] ,[ModEndDateTimeUtc] ,[EarliestExecutionDateTimeUtc], [ExecuteState])
				select distinct e.ReplicationTagEntityKey, 0, dateadd(millisecond,1,@CurrentStartUtc), @CurrentEndUtc,GETUTCDATE(),0 --2
				from ReplicationTagEntity e
				left outer join ReplicationSyncRequest q  -- Protects against duplicating existing queue records
					on q.ReplicationTagEntityKey = e.ReplicationTagEntityKey
					and q.ModStartDateTimeUtc = @CurrentStartLocal
					and q.ModEndDateTimeUtc = @CurrentEndLocal
				where e.ReplicationServerKey=@ReplicationKey
					and q.ReplicationTagEntityKey is null

			-- Report progress to console
			set @RepComment = ' Added ' + convert(nvarchar(10),@EntityCount) + ' items from ' + convert(nvarchar(50),@CurrentStartLocal,120) + ' to ' + convert(nvarchar(50),@CurrentEndLocal,120)
			print convert(nvarchar(50),getdate(),120) + @RepComment

			-- Estimate time remaining
			set @MinutesCovered = datediff(minute,@CurrentEndLocal,@NewestTimeLocal)
			set @MinutesElapsed = datediff(minute,@ExecutionStartUtc,getutcdate())
			if (@MinutesCovered > 0) and (@MinutesTotal>0)
				begin
					set @PercentComplete = @MinutesCovered / @MinutesTotal
					set @MinutesRemaining = @MinutesElapsed / @PercentComplete 
					print '           Estimated overall completion time: '+convert(nvarchar(50),dateadd(minute,@MinutesRemaining,getdate()),120)
				end

			-- Record progress in the "Annotation" table
			set @RepComment = @InvocationId + @RepComment
			exec aaAnnotationInsert @RepTag, null, null, null, @RepComment

			-- Give Replication some time to process the items just added to the queue
			set @WaitCount = 0
			set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
			while @WaitCount < @MaxWaitCount and @QueueSize > @MaxQueueReady
				begin
					set @WaitCount = @WaitCount + 1
					waitfor delay @WaitTime
					if (@WaitCount % 2 = 0)
						begin
							set @QueueSize = (select count(*) from ReplicationSyncRequestInfo where ReplicationServerKey=@ReplicationKey)
							set @RepComment = convert(nvarchar(50),getdate(),120)+ ' backfilling remaining ' + convert(nvarchar(10),@QueueSize) + ' items starting at ' + convert(nvarchar(50),@CurrentStartLocal,120)
							raiserror (@RepComment, 0, 1) with nowait -- Used to force update in Management Studio so messages are visible
						end
				end

			-- Move on to the previous block
			set @AllDone=1

			-- Base the time period to replicate on existing history blocks boundaries
			select top 1 @CurrentStartUtc=dateadd(minute,-TimeZoneOffset,FromDate), 
			@CurrentEndUtc=dateadd(minute,-TimeZoneOffset,ToDate), 
			@NextEndLocal=FromDate, --dateadd(minute,-1,FromDate),
			@CurrentStartLocal=FromDate,
			@CurrentEndLocal=ToDate,
			@AllDone=0
			from HistoryBlock
			where datediff(minute,FromDate,@NextEndLocal) > 0
			order by datediff(minute,FromDate,@NextEndLocal) asc, datediff(hour, FromDate, ToDate) desc

			if @QueueSize > @MaxQueueReady
				begin -- Queue processing is taking longer than  expected--something may be wrong, so bail out
					insert Annotation (TagName, Content, UserKey, DateTime) 
						values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
						@InvocationId+' backfill timed out',
						dbo.faaUser_ID(), getdate())
					print convert(nvarchar(50),getdate(),120)+' Timed out after running '+convert(nvarchar(10),datediff(minute,@ExecutionStartUtc,getutcdate()))+' minutes.'
					print ' '
					print 'After the queue is cleared, you can resume with:'
					print '   wwkbBackfillReplication '''+convert(nvarchar(50),@OldestTimeLocal,120)+''', '''+convert(nvarchar(50),@NextEndLocal,120)+''''
					print 'Exiting...'
					set @AllDone = 1
				end
			else if @CurrentStartLocal <= @OldestTimeLocal
				begin -- Finished the requested backfill
					insert Annotation (TagName, Content, UserKey, DateTime) 
						values('SysReplicationSyncQueueItems'+cast(@ReplicationKey as nvarchar(5)), 
						@InvocationId+' completed',
						dbo.faaUser_ID(), getdate())
					print convert(nvarchar(50),getdate(),120)+' Completed after '+convert(nvarchar(10),datediff(minute,@ExecutionStartUtc,getutcdate()))+' minutes.'
					print 'Processed '''+convert(nvarchar(50),@OldestTimeLocal,120)+''' to '''+convert(nvarchar(50),@NewestTimeLocal,120)+''''
					set @AllDone = 1
				end

		end
end
