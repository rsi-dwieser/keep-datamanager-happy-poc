SET NOCOUNT ON;

DECLARE @LocationId INT = $(LOCATION_ID);

;WITH LocationHierarchy AS (
    SELECT
        l.locationID,
        l.parentLocationID,
        l.ISAID,
        0 AS hop
    FROM dbo.Location l
    WHERE l.locationID = @LocationId

    UNION ALL

    SELECT
        p.locationID,
        p.parentLocationID,
        p.ISAID,
        lh.hop + 1
    FROM dbo.Location p
    INNER JOIN LocationHierarchy lh
        ON lh.parentLocationID = p.locationID
)
SELECT top(1) locationID
FROM LocationHierarchy
WHERE ISAID IS NOT NULL
ORDER BY hop ASC;