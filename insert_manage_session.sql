SET NOCOUNT ON;

INSERT INTO ManageSession (
    testtakerID,
    sectionID,
    testtakerStatusID,
    testSessionID,
    manageSessionGuid
)
OUTPUT INSERTED.manageSessionId
VALUES(
    $(TEST_TAKER_ID),          -- Student Test Taker ID
    $(SUBTEST_SECTION_ID),     -- Section ID for subtest
    5,                         -- 5 Approved - this will always be the status
    $(TEST_SESSION_ID),        -- FK -> dbo.TestSession(testSessionId)
    '$(SESSION_UUID)'
)