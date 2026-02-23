#!/bin/zsh

USER_ID=$1
SESSION_UUID=$2

run_sql() {
  local query="$1"

  sqlcmd -S 192.168.242.71,1435 \
        -d BASDM \
        -U basdm \
        -P "$DB_PASSWORD" \
        -h -1 -W \
        -b \
        -Q "SET NOCOUNT ON; $query" \
    | tr -d '\r'
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



echo "Keeping DataManager slightly content (but mostly not) since 2026:"

# locate the student ID and their location
fullName=$(run_sql "SELECT CONCAT(firstName,' ',lastName) FROM dbo.Users WHERE userID=${USER_ID};")
locationId=$(run_sql "select LocationID from Testtaker where userId = ${USER_ID};")
rosterId=$(run_sql "select rosterId from Testtaker where userId = ${USER_ID};")
locationName=$(run_sql "select locationName from Location where locationId = ${locationId};")
echo " User: $fullName ($USER_ID), location: ${locationName} (${locationId})"

# next we trace the location hierarchy to locate the ISA ID and Contract ID
parentLocationId=$(run_sql_file location.sql \
  -v LOCATION_ID="${locationId}" \
  -C)

isaId=$(run_sql "select ISAID from LOCATION where locationId=${parentLocationId};")
contractId=$(run_sql "select contractId from Contract where scoringIdentifierID=${isaId};")
parentLocationName=$(run_sql "select locationName from Location where locationId = ${parentLocationId};")
echo " Parent: ${parentLocationName} (${parentLocationId}), Contract: ${contractId}"

# is there a test event for the parent location?
echo " Locating test event"
testEventId=$(run_sql "select * from testEvent where contractId=${contractId} and testEventName='cogat.auto.1' and closeDate > GETDATE()")
if [[ -z "$testEventId" ]]; then
    echo " No test event found"
    testEventId=$(run_sql_file insert_test_event.sql \
      -v PARENT_LOCATION_ID="${parentLocationId}" \
         ROSTER_ID="${rosterId}" \
         CONTRACT_ID="${contractId}")
    echo " Created test event: ${testEventId}"
    run_sql_exec "insert into TestEventContent (testEventID, contentId, createUserId, createDateTime) values(${testEventId}, 72941, 13894655, GETDATE())"
    run_sql_exec "insert into TestEventContent (testEventID, contentId, createUserId, createDateTime) values(${testEventId}, 457, 13894655, GETDATE())"
    run_sql_exec "insert into TestEventLocation (testEventID, locationId, isActive, createUserId, createDateTime) values(${testEventId}, ${parentLocationId}, 1, 13894655, GETDATE())"

fi