SET NOCOUNT ON;

INSERT INTO dbo.StudentTestSessionSection (
    SectionId,
    actionId,
    currentAnswered,
    currentNumber,
    currentLocation,
    ManageSessionId,
    createDateTime,
    lastUpdatedDateTime,
    answers,
    Completed,
    testStatusId,
    minutesRemaining,
    numComplete,
    numQuestions
)
OUTPUT INSERTED.StudentTestSessionSectionId
VALUES (
    $(SUBTEST_SECTION_ID), 
    4,                       -- completed?
    0,                       -- current answered
    0,                       -- current number
    'Complete',
    '$(MANAGE_SESSION_ID)',
    GETDATE(),
    GETDATE(),
    '$(ANSWER_STRING)',
    1,                        -- Completed
    1,
    0,                        -- num complete
    0,                        -- num questions
    24
);