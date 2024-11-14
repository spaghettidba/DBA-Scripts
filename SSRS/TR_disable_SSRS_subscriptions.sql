CREATE TRIGGER TR_disable_SSRS_subscriptions ON sysjobs
FOR 
INSERT, UPDATE
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @job_id uniqueidentifier;

	DECLARE c CURSOR STATIC LOCAL FORWARD_ONLY READ_ONLY
	FOR
	SELECT job_id
	FROM sysjobs
	WHERE category_id = (
		SELECT category_id
		FROM syscategories
		WHERE name = 'Report Server'
	)
	AND enabled = 1;

	OPEN c 
	FETCH NEXT FROM c INTO @job_id

	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		EXEC sp_update_job @job_id = @job_id, @enabled = 0;

		FETCH NEXT FROM c INTO @job_id	
	END

	CLOSE c
	DEALLOCATE c
END
