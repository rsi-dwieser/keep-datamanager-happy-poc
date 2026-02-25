SET NOCOUNT ON;

INSERT INTO TestSession (
    sessionName,
    sessionCode,
    sectionID,
    testEventName,
    createUserID,
    testEventID,
    testGroupId,
    testLevelID,
    testAdmintype,
    gradeLevelID,
    openedByUserId,
    batteryID,
    testAdminTypeID,
    isOpenSession,
    sessionType,
    testingEngine,
    sessionStartDate
)
OUTPUT INSERTED.testSessionId
VALUES (
    '$(TEST_SESSION_NAME)',
    '$(SESSION_CODE)',                   -- each learnosity session gets it's own test session (for now?)
    $(SUBTEST_SECTION_ID),               -- This is the specific subtest being delivered
    '$(TEST_EVENT_NAME)',
    $(SERVICE_ACCOUNT_USER_ID),           
    $(TEST_EVENT_ID),
    $(TEST_GROUP_ID),                    -- reference to Content table, 458 is CogAT 7 Complete
    $(TEST_LEVEL_ID),                    -- Content table, 460 is Level 11
    'Audio-English',
    $(GRADE_LEVEL_ID),                   -- 17086548,5 - Five,5,1222306,5
    $(SERVICE_ACCOUNT_USER_ID),
    $(BATTERY_ID),                       -- From Section table -> Content. 721 = Verbal (parent of 460)
    3,                                   -- 3 = Audio-English
    0,                                   -- isOpenSession 
   'R',                                  -- sessionType
   'I',                                   -- testingEngine
    GETDATE()
);