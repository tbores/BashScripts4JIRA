#!/bin/bash
# ------------------------------------------------------------------
# [Thomas Bores] jira_download_all_attachments_in_project.sh
#          Description
#
#          This script search all issues with attachments in project
#          and delete them.
#          For test and security purposes, it has a demo mode :)
#
# Last version: https://github.com/tbores/BashScripts4JIRA
#
# Dependencies:
#     curl: https://curl.haxx.se/
#     jq: https://stedolan.github.io/jq/
# ------------------------------------------------------------------

# Functions
function usage {
    echo "Usage: $0 <jira_username> <jira_password> <project-key> <jira_url>"
    echo "  <username>        JIRA username"
    echo "  <password>        JIRA password"
    echo "  <project-key>     JIRA project key"
    echo "  <jira_url>        JIRA URL"
    echo ""
    echo "Example: $0 'tbores' 'thisIsNotMyPassword' 'TEMPONE' 'https://jira.myserver.de:8443'"
    echo "Quit with return code 1"
    exit 1
}

function execute_search {
    status_code=$(curl -s -u $JIRA_USERNAME:$JIRA_PASSWORD -o project.json -w "%{http_code}" -H 'Content-Type:application/json' -X GET $JIRA_URL'/rest/api/2/search?jql=project='${PROJECT_KEY}'+AND+attachments+is+not+EMPTY&maxResults=10000')

    if (($status_code != 200))
    then
        echo "Problem with the REST request"
        echo "HTTP_RETURN_CODE: "$status_code
        echo "Are you sure the project-key is correct?"
        echo "Quit with return code 3"
        exit 3
    else
        echo "Search request successful"
    fi
}

# Read input parameters
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]
then
    usage
fi

JIRA_USERNAME=$1
JIRA_PASSWORD=$2
PROJECT_KEY=$3
JIRA_URL=$4

echo "JIRA-Username: "$JIRA_USERNAME
#echo "JIRA-Password: "$JIRA_PASSWORD
echo "Project-Key: "$PROJECT_KEY
echo "JIRA URL: "$JIRA_URL

# Clean old files
rm -rf "attachments-$PROJECT_KEY"

if [ -e LOG_download_success.txt ];then
    rm LOG_download_success.txt
fi

if [ -e LOG_download_failed.txt ];then
    rm LOG_download_failed.txt
fi

# Create a folder for storing the attachments
mkdir "attachments-$PROJECT_KEY"
cd "attachments-$PROJECT_KEY"

# Execute search REST Request
execute_search

# Look for attachments
issue_index=0
n_issues=$(jq ".issues | length" project.json)

echo "Number of issues with attachments in project: "$n_issues

while [ $issue_index -lt $n_issues ];do
    echo "-----------"

    issue_url=$(jq ".issues[$issue_index].self" project.json)
    issue_url="${issue_url:1}"
    issue_url="${issue_url:0:-1}"

    issue_key=$(jq ".issues[$issue_index].key" project.json)
    issue_key="${issue_key:1}"
    issue_key="${issue_key:0:-1}"

    echo "Issue-key: "$issue_key
    echo "Issue-url: "$issue_url

    mkdir $issue_key
    cd $issue_key

    return_code=$(curl -s -u $JIRA_USERNAME:$JIRA_PASSWORD -o issue.json -w "%{http_code}" -H 'Content-Type:application/json' -X GET $issue_url)
    if (($return_code != 200))
    then
        echo "Get request failed!"
        echo "HTTP_RETURN_CODE: "$return_code
        echo "issue_url seems to be bad."
        echo "Quit with return code 4"
        exit 4
    else
        echo "Get request successful"
    fi

    attachment_index=0
    n_attachements=$(jq ".fields.attachment | length" issue.json)

    echo "Number of attachments: "$n_attachements

    while [ $attachment_index -lt $n_attachements ]; do
            attachment_id=$(jq ".fields.attachment[$attachment_index].id" issue.json)
            attachment_id="${attachment_id:1}"
            attachment_id="${attachment_id:0:-1}"

            attachment_filename=$(jq ".fields.attachment[$attachment_index].filename" issue.json)
            attachment_filename="${attachment_filename:1}"
            attachment_filename="${attachment_filename:0:-1}"

            # Handle specific case with attachments that have same filename
            if [ -e $attachment_filename ];then
                output_filename="$attachment_filename.1"
                echo "WARN: Attachment with $attachment_filename already exists. Rename it $output_filename"
            else
                output_filename=$attachment_filename
            fi

            if [ "$attachment_id" == "null" ]
            then
                echo "Url is empty"
            else
                echo "Attachment complete URL: $JIRA_URL/secure/attachment/$attachment_id/$attachment_filename"
                return_code=$(curl -s -G -o "$output_filename" -w "%{http_code}" -u $JIRA_USERNAME:$JIRA_PASSWORD -H 'Content-Type:application/json' -X GET "$JIRA_URL/secure/attachment/$attachment_id/" --data-urlencode "$attachment_filename")

                if (($return_code != 200))
                then
                    echo "ERROR: HTTP_RETURN_CODE: $return_code. Cannot download attachment $attachment_filename for issue $issue_key"
                    echo "HTTP_RETURN_CODE: $return_code. Cannot download attachment $attachment_filename for issue $issue_key" >> ../../LOG_download_failed.txt
                else
                    echo "INFO: Attachment $attachment_filename for issue $issue_key downloaded."
                    echo "Attachment $attachment_filename for issue $issue_key downloaded." >> ../../LOG_download_success.txt
                fi
            fi
            ((attachment_index++))
    done
    ((issue_index++))
    rm issue.json
    cd ..
done
rm project.json
cd ..
exit 0
