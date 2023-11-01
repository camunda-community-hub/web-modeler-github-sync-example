#!/bin/sh 

# ℹ️ Requires Bash 4 or newer, or zsh
# Recommended to run it on a test environment only and use as a template to build your own

# See these docs to obtain your Web Modeler client credentials: https://docs.camunda.io/docs/next/apis-tools/web-modeler-api/#authentication
MODELER_CLIENT_ID=YOUR-ID
MODELER_CLIENT_SECRET=YOUR-KEY
GITHUB_TOKEN=YOUR-KEY

PROJECT_ID=YOUR-MODELER-PROJECT-ID
REPO_NAME=YOUR-REPOSITORY-NAME
GITHUB_USER_NAME=YOUR-USER-NAME

# Color definitions for terminal output formatting
GREEN='\033[0;32m'
NC='\033[0m' # No Color
B=$(tput bold)
N=$(tput sgr0)
BGREEN=$GREEN$B
NNC=$NC$N

echo "------------------------------------------------------------------------"
echo "${BGREEN}SYNCING WEB MODELER WITH GITHUB${NNC}"
echo "Files are now synced to your disc, then to your repo..."
echo "------------------------------------------------------------------------"

echo ""

echo "[$(date +%s)] Sync started" >> sync.log

TOKEN=$(curl -s --header "Content-Type: application/json" --request POST --data "{\"grant_type\":\"client_credentials\", \"audience\":\"api.cloud.camunda.io\", \"client_id\":\"$MODELER_CLIENT_ID\", \"client_secret\":\"$MODELER_CLIENT_SECRET\"}" https://login.cloud.camunda.io/oauth/token | jq -r .access_token)

HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X GET "https://modeler.cloud.camunda.io/api/v1/projects/$PROJECT_ID" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN")

PROJECT=$(cat .curl_tmp)

# ECHO $PROJECT

#REPO_NAME=$(jq -r .metadata.name <<< "$PROJECT")
#PROJECT_ID=$(jq -r .metadata.name <<< "$PROJECT")

# ECHO $REPO_NAME

rm -r "$REPO_NAME"
# mkdir "$REPO_NAME"
# cd "$REPO_NAME"

git clone git@github.com:GITHUB_USER_NAME/$REPO_NAME.git

cd "$REPO_NAME"

BRANCH_ID="modeler-sync-$(date +%s)"
git switch -c "$BRANCH_ID"

rm -r *

download_file2()
{
    FILE="$1"

    _jq() {
        echo ${FILE} | base64 --decode | jq -r ${1}
    }

    FILE_ID=$(_jq '.id')
    FILE_PATH=$(_jq '.simplePath')

    FILE_NAME=${FILE_PATH##*/}

    if [[ "$FILE_PATH" == *"/"* ]]; then
        ONLY_PATH=${FILE_PATH%/*}
    else
        ONLY_PATH="./"
    fi

    ECHO "$ONLY_PATH"
    ECHO "$FILE_NAME"

    mkdir "$ONLY_PATH"
    touch "$FILE_PATH"

    # get milestones

    # MILESTONES_REQUEST="{
    #     \"filter\": {
    #         \"fileId\": \"$FILE_ID\"
    #     },
    #     \"sort\": [
    #         {
    #             \"field\": "created",
    #             \"direction\": "DESC"
    #         }
    #     ],
    #     \"size\": 2
    # }"

    # HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X POST "https://modeler.cloud.camunda.io/api/v1/milestones/search" \
    #     -H "Content-Type: application/json" \
    #     -H "Authorization: Bearer $TOKEN" \
    #     -d "$MILESTONES_REQUEST")

    # MILESTONES=$(cat .curl_tmp)

    # # get latest two
    # MILESTONES_COUNT=$(jq -r .total <<< "$MILESTONES")

    HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X GET "https://modeler.cloud.camunda.io/api/v1/files/$FILE_ID" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN")

    FILE_DETAILS=$(cat .curl_tmp)

    FILE_CONTENT=$(jq -r .content <<< "$FILE_DETAILS")

    # TODO better get latest milestone content, not draft state

    # TODO fix line break escaping behavior of bash 

    # FILE_CONTENT=$(tr -d '\n' <<< $FILE_CONTENT)

    echo "$FILE_CONTENT" > "$FILE_PATH"

    DIFF_LINK="https://modeler.cloud.camunda.io/diagrams/$FILE_ID/milestones"

    DIFF_LINKS="$DIFF_LINK, $DIFF_LINKS"
}


DIFF_LINKS=""

for file in $(echo $PROJECT | jq -r '.content.files[] | @base64'); do
   download_file2 "$file"
done

DIFF_LINKS=${DIFF_LINKS%??}

git add .
git commit -m "Web Modeler Sync"
git push -u origin "$BRANCH_ID"

cd ..

# create PR

# TODO create diff links

# TODO first fetch milestones of files
# TODO then fetch diff links

# TODO fetch collaborators

#PROJECT_COLLABORATORS=$(jq -r .metadata.name <<< "$PROJECT")

COLLAB_REQUEST="{
    \"filter\": {
        \"projectId\": \"$PROJECT_ID\"
    }
}"

HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X POST "https://modeler.cloud.camunda.io/api/v1/collaborators/search" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$COLLAB_REQUEST")

COLLAB_RESPONSE=$(cat .curl_tmp)

COLLABS=$(jq -r .items[].email <<< "$COLLAB_RESPONSE")

COLLABS_STRING=""

for collab in $(echo "$COLLABS"); do
    COLLABS_STRING="$collab, $COLLABS_STRING"
done

COLLABS_STRING=${COLLABS_STRING%??}

# TODO fetch from API
PROJECT_LINK="https://modeler.cloud.camunda.io/projects/$PROJECT_ID"

PR_BODY="Synced from Web Modeler. Project: $PROJECT_LINK \n\n Collaborators: $COLLABS_STRING \n\n Diff Links: $DIFF_LINKS"

PR="{
    \"title\": \"Web Modeler Sync\",
    \"body\": \"$PR_BODY\",
    \"head\": \"$BRANCH_ID\",
    \"base\": \"main\"
}"

HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/GITHUB_USER_NAME/$REPO_NAME/pulls \
  -d "$PR")

PR_RESPONSE=$(cat .curl_tmp)

PR_URL=$(jq -r ._links.html.href <<< "$PR_RESPONSE")
PR_NUMBER=$(jq -r .number <<< "$PR_RESPONSE")

# add collabs
# TODO lookup github handles

COLLABS_ARRAY="["
for collab in $(echo "$COLLABS"); do
    COLLABS_ARRAY="$COLLABS_ARRAY \"$collab\","
done

COLLABS_ARRAY=${COLLABS_ARRAY%?}
COLLABS_ARRAY="$COLLABS_ARRAY ]"

COLLABS_BODY="{
    \"reviewers\": $COLLABS_ARRAY
}"

echo "$COLLABS_BODY"

HTTP_STATUS=$(curl -s -o .curl_tmp -w "%{http_code}" -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/GITHUB_USER_NAME/$REPO_NAME/pulls/$PR_NUMBER/requested_reviewers \
  -d "$COLLABS_BODY")

REVIEWER_RESPONSE=$(cat .curl_tmp)

# add your browser here
open -a "Google Chrome" "$PR_URL"

# TODO invite Modeler collaborators as reviewers
# TODO link diff link to PR

# ------------------------------------
# ------------------------------------


