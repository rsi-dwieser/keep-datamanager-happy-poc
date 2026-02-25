#!/bin/zsh

USER_ID=$1
ASSIGNMENT_ID=$2
SESSION_UUID=$3
ANSWER_STRING=$4
RESULT_XML_FILE=$5
AGENT_STRING_FILE=$6

# read file contents safely (preserve newlines)
RESULT_XML=$(cat "$RESULT_XML_FILE")
AGENT_STRING=$(cat "$AGENT_STRING_FILE")


# this would be a known service account user that creates the placeholders in the DM DB.
# for now, this is my Danny DM 101 user
SERVICE_ACCOUNT_USER_ID=13894655

## this would be a mapping in the service for the assignments API

AUTO_EVENT_NAME="cogat.auto.02-25"

run_sql() {
  local query="$1"

  sqlcmd -S 192.168.242.71,1435 \
        -d BASDM \
        -U basdm \
        -P "$DB_PASSWORD" \
        -h -1 -W \
        -b \
        -Q "SET NOCOUNT ON; $query" \
    | tr -d '\r'\
}

run_sql_exec() {
  local query="$1"

  sqlcmd -S 192.168.242.71,1435 \
        -d BASDM \
        -U basdm \
        -P "$DB_PASSWORD" \
        -b \
        -Q "SET NOCOUNT ON; $query"

  if [ $? -ne 0 ]; then
    echo "SQL execution failed"
    exit 1
  fi
}

run_sql_file() {
  local file="$1"
  shift

  sqlcmd -S 192.168.242.71,1435 \
        -d BASDM \
        -U basdm \
        -P "$DB_PASSWORD" \
        -h -1 -W \
        -b \
        "$@" \
        -i "$file" \
    | tr -d '\r'
}



echo "=== KDMH: Keeping DataManager Happy since 2026 === "


echo "\n STEP 1: STUDENT & LOCATION\n"

# locate the student ID and their location
fullName=$(run_sql "SELECT CONCAT(firstName,' ',lastName) FROM dbo.Users WHERE userID=${USER_ID};")
locationId=$(run_sql "select LocationID from Testtaker where userId = ${USER_ID};")
gradeLevelId=$(run_sql "select gradeLevelId from Testtaker where userId = ${USER_ID};")
rosterId=$(run_sql "select rosterId from Testtaker where userId = ${USER_ID};")
locationName=$(run_sql "select locationName from Location where locationId = ${locationId};")
testTakerId=$(run_sql "select testTakerId from Testtaker where userId = ${USER_ID};")

echo " The only input we have is the **DM User ID** (${USER_ID}). 
 This is used to lookup the student information:
  - Name: ${fullName} (${USER_ID})
  - Grade Level: ${gradeLevelId}
  - Location: ${locationName} (${locationId})
  - Test Taker ID: ${testTakerId}"

# next we trace the location hierarchy to locate the ISA ID and Contract ID
parentLocationId=$(run_sql_file location.sql \
  -v LOCATION_ID="${locationId}" \
  -C)

isaId=$(run_sql "select ISAID from LOCATION where locationId=${parentLocationId};")
contractId=$(run_sql "select contractId from Contract where scoringIdentifierID=${isaId};")
parentLocationName=$(run_sql "select locationName from Location where locationId = ${parentLocationId};")
echo " Given the User record, we need to trace the roster hierarchy up to the parent to get a contract ID, which is required to create a Test Event."
echo "  Parent: ${parentLocationName} (${parentLocationId}), Contract: ${contractId}"

echo "\n STEP 2: TEST ASSIGNMENT\n"
echo " This service would take the assignment ID (${ASSIGNMENT_ID}) and use it to do a mapped lookup of all the necessary content IDs inside DM."
echo " DM stores a hierarchy of content as Assessment (CogAT) -> Form (Form 7) -> Group (Complete) -> Level (13/14) -> Battery (Verbal) -> Section (subtest)"

# lookup the assignment data
## This would be a mapping that we have of assignment service IDs to the related DM data
if [[ "$ASSIGNMENT_ID" = "CogAT_7_1314-VA" ]]; then
  FORM_CONTENT_ID=457 # Form 7
  TEST_GROUP_ID=458 # CogAT 7 Complete
  SUBTEST_SECTION_ID=1928 # VERBAL BATTERY: Test 1: Verbal Analogies 
  BATTERY_ID=721 # Verbal
  TEST_LEVEL_ID=462 # level 13/14
fi

formContentName=$(run_sql "select description from Content where contentID = ${FORM_CONTENT_ID};")
groupContentName=$(run_sql "select description from Content where contentID = ${TEST_GROUP_ID};")
levelContentName=$(run_sql "select description from Content where contentID = ${TEST_LEVEL_ID};")
batteryContentName=$(run_sql "select description from Content where contentID = ${BATTERY_ID};")
sectionName=$(run_sql "select title from section where sectionID=${SUBTEST_SECTION_ID}")

echo " ${ASSIGNMENT_ID} maps to:
  Form: ${formContentName} (${FORM_CONTENT_ID}) ->
   Group: ${groupContentName} (${TEST_GROUP_ID}) ->
    Level: ${levelContentName} (${TEST_LEVEL_ID}) ->
     Battery: ${batteryContentName} (${BATTERY_ID}) ->
      Section: ${sectionName} (${SUBTEST_SECTION_ID})"

echo " \n STEP 3: TEST EVENT \n"

echo " A Test Event (Order) connects an assessment to a student roster. This is automatically created _after_ the first student has completed testing for a specific assessment (i.e. CogAT).
 This service would auto-create a single test event for a combination of assessment, roster, and a fixed test period (like fall)."

# is there a test event for the parent location?
testEventId=$(run_sql "select testEventId from testEvent where contractId=${contractId} and testEventName='${AUTO_EVENT_NAME}' and closeDate > GETDATE()")
if [[ -z "$testEventId" ]]; then
  echo " No test event found"
  testEventId=$(run_sql_file insert_test_event.sql \
    -v PARENT_LOCATION_ID="${parentLocationId}" \
        TEST_EVENT_NAME="${AUTO_EVENT_NAME}" \
        ROSTER_ID="${rosterId}" \
        CONTRACT_ID="${contractId}")
  echo " Created test event: ${testEventId}"
  echo " Mapping Test Event Content: (${ASSIGNMENT_ID}) to DataManager Content ID ${FORM_CONTENT_ID} (CogAT Form 7)"
  run_sql_exec "insert into TestEventContent (testEventID, contentId, createUserId, createDateTime) values(${testEventId}, ${FORM_CONTENT_ID}, ${SERVICE_ACCOUNT_USER_ID}, GETDATE())"
  echo " Mapping Test Event Location: ${parentLocationName}"
  run_sql_exec "insert into TestEventLocation (testEventID, locationId, isActive, createUserId, createDateTime) values(${testEventId}, ${parentLocationId}, 1, ${SERVICE_ACCOUNT_USER_ID}, GETDATE())"
else
  testEventName=$(run_sql "select testEventName from testEvent where testEventId=${testEventId}")
  echo " Located existing test event: ${testEventName} (${testEventId})"
fi

echo " \n STEP 4: TEST SESSION\n"

current_date=$(date +"%Y-%m-%d")
testSessionName="${ASSIGNMENT_ID} ${USER_ID} ${current_date}"
sessionCode="${testEventId}-${SUBTEST_SECTION_ID}"
testSessionId=$(run_sql "select testSessionId from testSession where sessionCode='${sessionCode}'")

echo " Typically DM creates a test session per date/grade/test/level. To keep DM happy we create a singular session per assignment/user:
  Session Name: ${testSessionName}
  Session Code: ${sessionCode}"

if [[ -z "$testSessionId" ]]; then
  testSessionId=$(run_sql_file insert_test_session.sql \
        -v TEST_SESSION_NAME="${testSessionName}" \
          SESSION_UUID="${SESSION_UUID}" \
          TEST_EVENT_NAME="${AUTO_EVENT_NAME}" \
          SERVICE_ACCOUNT_USER_ID="${SERVICE_ACCOUNT_USER_ID}" \
          TEST_EVENT_ID="${testEventId}" \
          GRADE_LEVEL_ID="${gradeLevelId}" \
          TEST_LEVEL_ID="${TEST_LEVEL_ID}" \
          BATTERY_ID="${BATTERY_ID}" \
          TEST_GROUP_ID="${TEST_GROUP_ID}" \
          SUBTEST_SECTION_ID="${SUBTEST_SECTION_ID}" \
          SESSION_CODE="${sessionCode}")
  echo " Created Test Session: ${testSessionName} (${testSessionId})"
else
  echo " Located existing Test Session: ${sessionCode} (${testSessionId})"
fi

echo " \n STEP 5: STUDENT MANAGED SESSION\n"

manageSessionId=$(run_sql "select manageSessionId from manageSession where manageSessionGuid='${SESSION_UUID}'")
if [[ -z "$manageSessionId" ]]; then
  manageSessionId=$(run_sql_file insert_manage_session.sql \
    -v TEST_TAKER_ID="${testTakerId}" \
       SUBTEST_SECTION_ID="${SUBTEST_SECTION_ID}" \
       TEST_SESSION_ID="${testSessionId}" \
       SESSION_UUID="${SESSION_UUID}"
  )
  echo " Created Student Managed Session: ${manageSessionId}"
else
  echo " Located existing Student Managed Session: ${manageSessionId}"
fi

echo " \n STEP 6: STUDENT TEST SESSION SECTION\n"
testSessionSectionId=$(run_sql "select StudentTestSessionSectionId from StudentTestSessionSection where ManageSessionId='${manageSessionId}'")
if [[ -z "$testSessionSectionId" ]]; then
  testSessionSectionId=$(run_sql_file insert_student_test_session_section.sql \
    -v MANAGE_SESSION_ID="${manageSessionId}" \
       SUBTEST_SECTION_ID="${SUBTEST_SECTION_ID}" \
       ANSWER_STRING="${ANSWER_STRING}")
  echo " Created Student Test Session Section: ${testSessionSectionId} with answer string '${ANSWER_STRING}'"
else
  echo " Updating (TODO)"
fi

echo " \n STEP 7: TEST COMPLETE SERVICE\n"
testCompleteServiceId=$(run_sql "select testCompleteServiceId from TestCompleteService where sessionId='${manageSessionId}'")
if [[ -z "$testCompleteServiceId" ]]; then
  testCompleteServiceId=$(run_sql_file insert_test_complete_service.sql \
    -v TEST_SESSION_ID="${testSessionId}" \
       USER_ID="${USER_ID}" \
       RESULT_XML="${RESULT_XML}" \
       AGENT_STRING="${AGENT_STRING}")
  echo " Created Test Complete Service record: ${testCompleteServiceId}"
else
  echo " Updating (TODO)"
fi