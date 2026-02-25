SET NOCOUNT ON;

INSERT INTO dbo.TestCompleteService (
    program,
    environment,
    sessionId,
    studentId,
    resultXML,
    agentString,
    securityCode,
    createdDate,
    languageCode
)
OUTPUT INSERTED.testCompleteServiceId
VALUES (
    'ITBSCOGAT',
    114,
    $(TEST_SESSION_ID),
    $(USER_ID),
    '$(RESULT_XML)',
    '$(AGENT_STRING)',
    NEWID(),
    GETDATE(),
    'ENU'
);