#!/bin/bash

if [[ -n "${sonarr_eventtype}" ]]; then
  FILE_PATH=${sonarr_episodefile_path}
  EVENT_TYPE="${sonarr_eventtype}"
elif [[ -n "${radarr_eventtype}" ]]; then
  FILE_PATH=${radarr_moviefile_path}
  EVENT_TYPE="${radarr_eventtype}"
fi

if [[ -n "${FF_PATH_TRANSLATE}" ]]; then
  FILE_PATH=$(echo "$FILE_PATH" | sed "s|${FF_PATH_TRANSLATE}|")
fi

FILESEARCH="{\"Path\": \"${FILE_PATH}\"}"
PAYLOAD="{\"FlowUid\": \"${FF_FLOW_ID}\", \"Files\": [\"${FILE_PATH}\"]}"

# debug logs - payload is most important
echo "EVENT_TYPE: $EVENT_TYPE"
echo "FF_URL: $FF_URL"
echo "PAYLOAD: $PAYLOAD"

# don't call FF when testing
if [[ -n "$EVENT_TYPE" && "$EVENT_TYPE" != "Test" ]]; then
  FILE_UID=$(curl --silent --request POST \
    --url ${FF_URL}/api/library-file/search \
    --header 'content-type: application/json' \
    --data "$FILESEARCH" \
    --location \
    --insecure | jq '.[].Uid')

  echo "FILE_UID: $FILE_UID"

  REPROC="{\"Uids\": [${FILE_UID}], \"BottomOfQueue\": true}"

  if [[ -n "$FILE_UID" ]]; then
    echo "Reprocessing file"
    curl --silent --request POST \
      --url ${FF_URL}/api/library-file/reprocess \
      --header 'content-type: application/json' \
      --data "$REPROC" \
      --location \
      --insecure
  else
    echo "File not found, adding."
    curl --silent --request POST \
      --url ${FF_URL}/api/library-file/manually-add \
      --header 'content-type: application/json' \
      --data "$PAYLOAD" \
      --location \
      --insecure
  fi

fi

