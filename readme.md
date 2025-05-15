# upload_snow_attachment Action

This action uploads a file to a record in ServiceNow.

## GitHub Action Use

To use this action in your workflow, invoke like the following:

```yaml
name: Upload file to ServiceNow CHG

on:
  push:
    tags:
    - '*'

env:
  SN_URL: "https://my_company.service-now.com"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v2

      - name: Upload file
        uses: bwhitehead0/upload_snow_attachment@v1
        with: 
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_record_sys_id: "ec961b23d2c5b131b950339f034bcbd7"
          upload_file: "/path/to/file"
```

### Inputs

* `snow_url`: ServiceNow URL (e.g., https://my-company.service-now.com). **Required**.
* `snow_user`: ServiceNow username (Username + password or token are required). **Required**.
* `snow_password`: ServiceNow password (Username + password or token are required). **Required**.
* `snow_client_id`: ServiceNow Client ID for oAuth Token auth. **Optional** (Requires: User + pass + client ID + client secret).
* `snow_client_secret`: ServiceNow Client Secret for oAuth Token auth. **Optional** (Requires: User + pass + client ID + client secret).
* `snow_record_sys_id`: ServiceNow record sys_id. **Required**. (*See below ℹ️ note*)
* `upload_file`: Path to file to attach. **Required**.
* `debug`: Enable debug output. **Optional**.
* `snow_timeout`: Timeout for ServiceNow API call. **Optional**, default='60'.

> **ℹ️ snow_record_sys_id**: At present (v1,v1.0.0) this action uploads the attachment using the `change_request` table name. Future versions will support determing the correct table name based on the record type.

### Outputs

* `response`: The full JSON response from the ServiceNow API

## Example with other ServiceNow CHG actions

Your ticket workflow requirements may vary, but this example creates a new CHG ticket, updates the ticket to start a deployment, does some dummy deployment activity, updates the ticket notes, and moves the ticket towards closure, eventually closing the ticket with close notes.

> **⚠️ Note about multiline strings:** Due both to the limitations of GitHub Actions inputs, as well as the nature of the JSON payload sent to the ServiceNow API, constructing multiline values for fields that accept multiline input, such as `work_notes`, `close_notes`, etc, for now it is recommended to build the string in its own step using component variables for human readability and clarity. Include newlines `\r\n` in these variables, and then concatenate them when writing either to `$GITHUB_ENV` or `$GITHUB_OUTPUT`. Examples of this are found in the below workflow steps named `Create work_notes message` and `Create post-deploy work_notes message`.

```yaml
name: Example CD workflow

on:
  push:
    tags:
    - '*'
env:
  SN_CI: "My CI"
  SN_URL: "https://my_company.service-now.com"
  ENV: "QAT"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
      
      - name: Get workflow job ID
        # for use with full link to workflow run in SN ticket notes
        id: job_id
        uses: bwhitehead0/get_job_id@main
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Create CHG Ticket
        id: new_change
        uses: bwhitehead0/create_snow_change@v1
        with:
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_ci: ${{ env.SN_CI }}
          change_title: "Deploying tag ${{ github.ref_name }}"
          change_description: "Automated deployment for tag ${{ github.ref_name }}"
      
      - name: Create work_notes message
        run: |
          LOG_URL="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}/job/${{ steps.job_id.outputs.job_id }}"

          WORKFLOW_STEP_MESSAGE="Dummy worknotes message. Using the old API action method. Starting deployment to ${{ env.ENV }} environment via GitHub Actions. See below and workflow logs for additional details.\r\n"

          GITHUB_USER="GitHub User: $GITHUB_ACTOR\r\n"
          GITHUB_REPOSITORY="GitHub Repo: ${{ github.repository }}\r\n"
          CHANGE_TICKET="Change Ticket: ${{ steps.new_change.outputs.change_ticket_number }}\r\n"
          DEPLOYMENT_TAG="Deployment Tag: ${{ github.ref_name }}\r\n"
          DEPLOYMENT_ENV="Deployment Environment: ${{ env.ENV }}\r\n"
          GITHUB_RUN_ID="GitHub Workflow ID: ${{ github.run_id }}\r\n"
          GITHUB_ACTIONS_URL="Workflow Log: [code]<a href=$LOG_URL target=_blank>$LOG_URL</a>[/code]"

          echo "WORKNOTES_SINGLELINE=$WORKFLOW_STEP_MESSAGE$GITHUB_USER$GITHUB_REPOSITORY$CHANGE_TICKET$DEPLOYMENT_TAG$DEPLOYMENT_ENV$GITHUB_RUN_ID$USER_COMMENT$GITHUB_ACTIONS_URL" >> $GITHUB_ENV

      - name: Update CHG
        uses: bwhitehead0/update_snow_change@v1
        with: 
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_change_sys_id: ${{ steps.new_change.outputs.change_ticket_sys_id }}
          snow_change_work_notes: ${{ env.WORKNOTES_SINGLELINE }}
          snow_change_state: -1
      
      - name: Example deployment work
        id: deployment
        run: |
          echo "Your deployment operations here."
          # example command output, send to GITHUB_OUTPUT to address later, or, write to file now to pick up in upload step
          echo "deployment_data=$(ls -lah | md5sum)" >> $GITHUB_OUTPUT
          echo "deployment_status=Success" >> $GITHUB_OUTPUT
      
      - name: Write deployment output
        run: |
          echo "${{ steps.deployment.outputs.deployment_data }}" > deployment_data.txt

      - name: Upload deployment output to ServiceNow
        uses: bwhitehead0/upload_snow_attachment@v1
        with:
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_record_sys_id: ${{ steps.new_change.outputs.change_ticket_sys_id }}
          upload_file: deployment_data.txt
      
      - name: Create post-deploy work_notes message
        run: |
          LOG_URL="${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}/job/${{ steps.job_id.outputs.job_id }}"

          WORKFLOW_STEP_MESSAGE="Deployment complete with status: ${{ steps.deployment.outputs.deployment_status }}\r\n
          
          See below and workflow logs for additional details.\r\n"

          GITHUB_USER="GitHub User: $GITHUB_ACTOR\r\n"
          GITHUB_REPOSITORY="GitHub Repo: ${{ github.repository }}\r\n"
          CHANGE_TICKET="Change Ticket: ${{ steps.new_change.outputs.change_ticket_number }}\r\n"
          DEPLOYMENT_TAG="Deployment Tag: ${{ github.ref_name }}\r\n"
          DEPLOYMENT_ENV="Deployment Environment: ${{ env.ENV }}\r\n"
          GITHUB_RUN_ID="GitHub Workflow ID: ${{ github.run_id }}\r\n"
          GITHUB_ACTIONS_URL="Workflow Log: [code]<a href=$LOG_URL target=_blank>$LOG_URL</a>[/code]"

          echo "WORKNOTES_SINGLELINE=$WORKFLOW_STEP_MESSAGE$GITHUB_USER$GITHUB_REPOSITORY$CHANGE_TICKET$DEPLOYMENT_TAG$DEPLOYMENT_ENV$GITHUB_RUN_ID$USER_COMMENT$GITHUB_ACTIONS_URL" >> $GITHUB_ENV
      
      - name: Update CHG post-deployment
        uses: bwhitehead0/update_snow_change@v1
        with: 
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_change_sys_id: ${{ steps.new_change.outputs.change_ticket_sys_id }}
          snow_change_work_notes: ${{ env.WORKNOTES_SINGLELINE }}
      
      - name: Get CHG Ticket Details
        id: change_detail
        uses: bwhitehead0/get_snow_change@v1
        with:
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          change_ticket_number: ${{ steps.new_change.outputs.change_ticket_number }}
          snow_timeout: "60"
          debug: "false"

      - name: Display CHG details
        run: |
          echo "CHG sys_id: ${{ steps.change_detail.outputs.change_sys_id }}"
          echo "CHG type: ${{ steps.change_detail.outputs.change_type }}"
          echo "CHG requested by: ${{ steps.change_detail.outputs.change_requested_by }}"
          echo "CHG CAB review: ${{ steps.change_detail.outputs.change_cab_reviewed }}"
          echo "CHG state: ${{ steps.change_detail.outputs.change_state }}"
          echo "CHG state code: ${{ steps.change_detail.outputs.change_state_code }}"
          echo "CHG start date: ${{ steps.change_detail.outputs.change_start_date }}"
          echo "CHG end date: ${{ steps.change_detail.outputs.change_end_date }}"
          echo "CHG cmdb_ci: ${{ steps.change_detail.outputs.change_cmdb_ci }}"
          echo "CHG cmdb_ci sys_id: ${{ steps.change_detail.outputs.change_cmdb_ci_sys_id }}"
          printf '%s\n' 'CHG Detail: ${{ steps.change_detail.outputs.change_detail }}'
      
      - name: Prep close ticket
        run: |
          close_notes="Closing CHG ticket with status: ${{ steps.deployment.outputs.deployment_status }}"
          if [[ ${{ steps.deployment.outputs.deployment_status }} == "Success" ]]; then
            close_code="Successful"
          else
            close_code="Unsuccessful"
          fi
          echo "close_notes=$close_notes" >> $GITHUB_ENV
          echo "close_code=$close_code" >> $GITHUB_ENV

      - name: Set CHG ticket to review
        uses: bwhitehead0/update_snow_change@v1
        with: 
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_change_sys_id: ${{ steps.new_change.outputs.change_ticket_sys_id }}
          snow_change_state: 0

      - name: Close CHG ticket
        uses: bwhitehead0/update_snow_change@v1
        with: 
          snow_url: ${{ env.SN_URL }}
          snow_user: ${{ secrets.mySnowUser }}
          snow_password: ${{ secrets.mySnowPass }}
          snow_client_id: ${{ secrets.mySnowPass }}
          snow_client_secret: ${{ secrets.mySnowClientId }}
          snow_change_sys_id: ${{ steps.new_change.outputs.change_ticket_sys_id }}
          snow_change_state: 3
          snow_change_close_code: ${{ env.close_code }}
          snow_change_close_notes: ${{ env.close_notes}}
```
