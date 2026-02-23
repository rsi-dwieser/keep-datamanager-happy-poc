#!/bin/zsh

USER_ID=$1
ASSIGNMENT_ID=$2
SESSION_UUID=$3

# this would be a known service account user that creates the placeholders in the DM DB.
# for now, this is my Danny DM 101 user
SERVICE_ACCOUNT_USER_ID=13894655

## this would be a mapping in the service for the assignments API
COGAT_7_CONTENT=457

AUTO_EVENT_NAME="cogat.auto.3"

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


echo "\n STEP 1: STUDENT AND ASSIGNMENT\n"

# locate the student ID and their location
fullName=$(run_sql "SELECT CONCAT(firstName,' ',lastName) FROM dbo.Users WHERE userID=${USER_ID};")
locationId=$(run_sql "select LocationID from Testtaker where userId = ${USER_ID};")
gradeLevelId=$(run_sql "select gradeLevelId from Testtaker where userId = ${USER_ID};")
rosterId=$(run_sql "select rosterId from Testtaker where userId = ${USER_ID};")
locationName=$(run_sql "select locationName from Location where locationId = ${locationId};")
echo " User: $fullName ($USER_ID), gradeLevelId: ${gradeLevelId}, location: ${locationName} (${locationId})"


# lookup the assignment data
## This would be a mapping that we have of assignment service IDs to the related DM data
if [[ "$ASSIGNMENT_ID" = "CogAT_7_1314-VA" ]]; then
  TEST_GROUP_ID=458 # CogAT 7 Complete
  SUBTEST_SECTION_ID=1928 # VERBAL BATTERY: Test 1: Verbal Analogies 
  BATTERY_ID=721 # Verbal
  TEST_LEVEL_ID=462 # level 13/14
fi

echo " Test Group ($TEST_GROUP_ID), Test Battery: ${BATTERY_ID}, Test Level: ${TEST_LEVEL_ID}, Subtest Section ${SUBTEST_SECTION_ID}"


# next we trace the location hierarchy to locate the ISA ID and Contract ID
parentLocationId=$(run_sql_file location.sql \
  -v LOCATION_ID="${locationId}" \
  -C)

isaId=$(run_sql "select ISAID from LOCATION where locationId=${parentLocationId};")
contractId=$(run_sql "select contractId from Contract where scoringIdentifierID=${isaId};")
parentLocationName=$(run_sql "select locationName from Location where locationId = ${parentLocationId};")
echo " Parent: ${parentLocationName} (${parentLocationId}), Contract: ${contractId}"

echo " \n STEP 2: TEST EVENT \n"

# is there a test event for the parent location?
echo " Locating test event"
testEventId=$(run_sql "select testEventId from testEvent where contractId=${contractId} and testEventName='${AUTO_EVENT_NAME}' and closeDate > GETDATE()")
if [[ -z "$testEventId" ]]; then
  echo " No test event found"
  testEventId=$(run_sql_file insert_test_event.sql \
    -v PARENT_LOCATION_ID="${parentLocationId}" \
        TEST_EVENT_NAME="${AUTO_EVENT_NAME}" \
        ROSTER_ID="${rosterId}" \
        CONTRACT_ID="${contractId}")
  echo " Created test event: ${testEventId}"
  echo " Mapping Test Event Content: (${ASSIGNMENT_ID}) to DataManager Content ID ${COGAT_7_CONTENT} (CogAT Form 7)"
  run_sql_exec "insert into TestEventContent (testEventID, contentId, createUserId, createDateTime) values(${testEventId}, ${COGAT_7_CONTENT}, ${SERVICE_ACCOUNT_USER_ID}, GETDATE())"
  echo " Mapping Test Event Location: ${parentLocationName}"
  run_sql_exec "insert into TestEventLocation (testEventID, locationId, isActive, createUserId, createDateTime) values(${testEventId}, ${parentLocationId}, 1, ${SERVICE_ACCOUNT_USER_ID}, GETDATE())"
else
  testEventName=$(run_sql "select testEventName from testEvent where testEventId=${testEventId}")
  echo " Located test event: ${testEventName}(${testEventId})"
fi

echo " \n STEP 3: TEST SESSION\n"

current_date=$(date +"%Y-%m-%d")
testSessionName="${ASSIGNMENT_ID} ${USER_ID} ${current_date}"
sessionCode="${testEventId}-${SUBTEST_SECTION_ID}"
testSessionId=$(run_sql "select testSessionId from testSession where sessionCode='${sessionCode}'")
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
  echo " Located Test Session: ${sessionCode}(${testSessionId})"
fi

echo " \n STEP 3: MANAGE SESSION\n"
