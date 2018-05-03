/*

Summarize Current SQL Server Client Load
========================================

This set of queries gives a high-level characterization of the current load placed on SQL Server by client
node, user and application. These queries only reflect active client connections. They are generally not 
specific to Wonderware Historian, but as provided are filtered to only include the load on the "Runtime" database. 

The results can be helpful to narrow down the clients which are causing the highest query load on the system.
If additional detail is needed, use SQL Profiler to capture the specific queries, optionally filtering
the trace based to specific clients/applications identified by these queries.

Revised: 3-May-2018
By: E. Middleton

*/


-- Summarize Load By Database
select 
	DB_NAME(dbid) as [Database]
	,count(*) as Processes
	,min(p.login_time) as FirstJob
	,max(p.last_batch) as LastJob
	,datediff(minute,min(p.login_time),max(p.last_batch)) as Minutes
	,sum(p.cpu) as CPUUsage
	,sum(p.physical_io) as IOUsage
	,sum(p.memusage) as MemUsage
	from master.dbo.sysprocesses p with (nolock)
	join master.sys.dm_exec_connections c  with (nolock)
		on c.session_id=p.spid
		and parent_connection_id is null
	group by dbid
	order by DB_NAME(dbid)


-- Summarize Load By Application (independent of client node)
select 
	[program_name] as Application
	--,case when p.last_batch > a.LastTime then p.last_batch LastTime
	,count(*) as Processes
	,min(p.login_time) as FirstJob
	,max(p.last_batch) as LastJob
	,datediff(minute,min(p.login_time),max(p.last_batch)) as Minutes
	,sum(p.cpu) as CPUUsage
	,sum(p.physical_io) as IOUsage
	,sum(p.memusage) as MemUsage
	from master.dbo.sysprocesses p with (nolock)
	join master.sys.dm_exec_connections c  with (nolock)
		on c.session_id=p.spid
		and parent_connection_id is null
	where (
		DB_NAME(dbid)='Runtime' -- Remove/change this to include other databases
		and hostprocess <> ''
	) or (dbid is null and hostprocess is null)
	group by program_name
	order by CPUUsage desc
	
-- Summarize Load By Application, Client Node, and Login
select p.hostname as Node
	,p.loginame as UserName
	,[program_name] as Application
	,p.net_address as MACAddress
	,c.client_net_address as IPAddress
	--,case when p.last_batch > a.LastTime then p.last_batch LastTime
	,count(*) as Processes
	,min(p.login_time) as FirstJob
	,max(p.last_batch) as LastJob
	,datediff(minute,min(p.login_time),max(p.last_batch)) as Minutes
	,sum(p.cpu) as CPUUsage
	,sum(p.physical_io) as IOUsage
	,sum(p.memusage) as MemUsage
	from master.dbo.sysprocesses p with (nolock)
	join master.sys.dm_exec_connections c  with (nolock)
		on c.session_id=p.spid
		and parent_connection_id is null
	where (
		DB_NAME(dbid)='Runtime' -- Remove/change this to include other databases
		and hostprocess <> ''
	) or (dbid is null and hostprocess is null)
	group by p.hostname, program_name, p.loginame, p.net_address, c.client_net_address
	order by program_name, CPUUsage desc
