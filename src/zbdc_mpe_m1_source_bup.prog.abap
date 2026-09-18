
"& Include ZBDC_MPE_M1_SOURCE_BUP
"& Purpose Local, Gmail, Google Drive and REST adapters
*& remote exact-version ingest state repair

"& Gmail Dynamic Form Pending Submission Pull
"& Purpose:
"& Screen 0300 uses Gmail like another inbound upload source.
"& ABAP calls n8n WF4, lets the user select one or more submissions,
"& converts dynamic rows with the existing registry mapping, persists
"& the current upload sessions, and leaves Preview/Staging/Execution
"& to the existing generic flow.

"& No new DDIC object, no TCODE CASE, no transaction-specific builder.

"& Gmail WF4 Reliable Pull
"& - Derives WF4 URL from the existing WF1 production webhook when needed
"& - Wakes Render/n8n through /healthz/readiness
"& - Retries transient communication/HTTP failures after 5 seconds
"& - Returns exact URL/auth/HTTP/SSL diagnostics instead of a generic error

TYPES: BEGIN OF ty_m1_gmail_submission,
         submission_id TYPE c LENGTH 100,
         request_id    TYPE c LENGTH 100,
         tcode         TYPE zbdc_prof_bup-tcode,
         profile       TYPE zbdc_prof_bup-profile_name,
         version       TYPE zbdc_prof_bup-profile_ver,
         row_count     TYPE i,
         submitted_at  TYPE c LENGTH 40,
         status        TYPE c LENGTH 30,
         source        TYPE c LENGTH 30,
         rows_json     TYPE string,
       END OF ty_m1_gmail_submission.
TYPES ty_t_m1_gmail_submission
      TYPE STANDARD TABLE OF ty_m1_gmail_submission
      WITH DEFAULT KEY.

"Browse and Upload/Ingest are two separate boundaries on screen 0300.
"For Gmail, Browse stores the exact pending submissions selected by the user;
"UPLOAD/INGEST is the only action allowed to convert them into staging rows.
DATA gt_m1_gmail_selected_pending TYPE ty_t_m1_gmail_submission.

TYPES: BEGIN OF ty_m1_gmail_popup,
         mark          TYPE c LENGTH 1,
         sel_no        TYPE c LENGTH 4,
         request_id    TYPE c LENGTH 80,
         tcode         TYPE c LENGTH 20,
         profile       TYPE c LENGTH 40,
         version       TYPE c LENGTH 12,
         row_count     TYPE i,
         submitted_at  TYPE c LENGTH 30,
         submission_id TYPE c LENGTH 100,
       END OF ty_m1_gmail_popup.
TYPES ty_t_m1_gmail_popup
      TYPE STANDARD TABLE OF ty_m1_gmail_popup
      WITH DEFAULT KEY.

FORM normalize_gmail_pull_url
  USING    iv_candidate TYPE string
  CHANGING cv_url       TYPE string
           cv_ok        TYPE abap_bool.

  DATA: lv_candidate   TYPE string,
        lv_webhook_pos TYPE i,
        lv_prefix_len  TYPE i,
        lv_prefix      TYPE string.

  CLEAR: cv_url, cv_ok.

  lv_candidate = iv_candidate.
  CONDENSE lv_candidate NO-GAPS.

  IF lv_candidate IS INITIAL
  OR lv_candidate NP 'https://*'.
    RETURN.
  ENDIF.

  IF lv_candidate CS '/webhook/sap-bdc-gmail-pull-pending'.
    cv_url = lv_candidate.
    cv_ok  = abap_true.
    RETURN.
  ENDIF.

 "WF1 and WF4 are on the same n8n host. Reuse the configured production
 "webhook base and replace only the path, never the host or credential.
  FIND FIRST OCCURRENCE OF '/webhook/'
    IN lv_candidate
    MATCH OFFSET lv_webhook_pos.

  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_prefix_len = lv_webhook_pos + strlen( '/webhook/' ).
  lv_prefix = lv_candidate+0(lv_prefix_len).

  cv_url = |{ lv_prefix }sap-bdc-gmail-pull-pending|.
  cv_ok  = abap_true.
ENDFORM.

FORM get_gmail_pull_url
  CHANGING cv_url TYPE string
           cv_ok  TYPE abap_bool.

  DATA: lv_candidate TYPE string,
        lv_url_ok    TYPE abap_bool.

  CLEAR: cv_url, cv_ok.

 "1. Dedicated WF4 URL has the highest priority.
  PERFORM get_config_value
    USING    'N8N_GMAIL_PULL_URL'
    CHANGING lv_candidate.

  PERFORM normalize_gmail_pull_url
    USING    lv_candidate
    CHANGING cv_url lv_url_ok.

  IF lv_url_ok = abap_true.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

 "2. Reuse the already working WF1 production URL and derive WF4 on the
 "same n8n host. This avoids a new loader report or a new DDIC field.
  CLEAR: lv_candidate, lv_url_ok.
  PERFORM get_config_value
    USING    'N8N_GMAIL_REQUEST_URL'
    CHANGING lv_candidate.

  PERFORM normalize_gmail_pull_url
    USING    lv_candidate
    CHANGING cv_url lv_url_ok.

  IF lv_url_ok = abap_true.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

 "3. Backward-compatible runtime/config URL fallback.
  CLEAR: lv_candidate, lv_url_ok.
  PERFORM get_config_value
    USING    'WEBHOOK_URL'
    CHANGING lv_candidate.

  PERFORM normalize_gmail_pull_url
    USING    lv_candidate
    CHANGING cv_url lv_url_ok.

  IF lv_url_ok = abap_true.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  CLEAR: lv_candidate, lv_url_ok.
  PERFORM load_source_config.
  lv_candidate = txtp_webhook_url.

  PERFORM normalize_gmail_pull_url
    USING    lv_candidate
    CHANGING cv_url lv_url_ok.

  IF lv_url_ok = abap_true.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  CLEAR cv_url.
ENDFORM.

FORM build_n8n_readiness_url
  USING    iv_pull_url      TYPE string
  CHANGING cv_readiness_url TYPE string
           cv_ok            TYPE abap_bool.

  DATA: lv_pull_url    TYPE string,
        lv_webhook_pos TYPE i,
        lv_host        TYPE string.

  CLEAR: cv_readiness_url, cv_ok.

  lv_pull_url = iv_pull_url.
  CONDENSE lv_pull_url NO-GAPS.

  FIND FIRST OCCURRENCE OF '/webhook/'
    IN lv_pull_url
    MATCH OFFSET lv_webhook_pos.

  IF sy-subrc <> 0 OR lv_webhook_pos <= 0.
    RETURN.
  ENDIF.

  lv_host = lv_pull_url+0(lv_webhook_pos).
  cv_readiness_url = |{ lv_host }/healthz/readiness|.
  cv_ok = abap_true.
ENDFORM.

FORM wake_n8n
  USING    iv_pull_url TYPE string
           iv_timeout  TYPE i
  CHANGING cv_ok       TYPE abap_bool
           cv_message  TYPE string.

  DATA: lo_client        TYPE REF TO if_http_client,
        lv_readiness_url TYPE string,
        lv_url_ok        TYPE abap_bool,
        lv_http_code     TYPE i,
        lv_send_rc       TYPE sy-subrc,
        lv_receive_rc    TYPE sy-subrc,
        lv_attempt       TYPE i,
        lv_timeout       TYPE i.

  CLEAR: cv_ok, cv_message.

  PERFORM build_n8n_readiness_url
    USING    iv_pull_url
    CHANGING lv_readiness_url lv_url_ok.

  IF lv_url_ok <> abap_true.
    cv_message = 'Cannot derive the n8n readiness URL from the WF4 URL.'.
    RETURN.
  ENDIF.

  lv_timeout = iv_timeout.
  IF lv_timeout < 1 OR lv_timeout > 600.
    cv_message = 'n8n readiness timeout must be between 1 and 600 seconds.'.
    RETURN.
  ENDIF.

    MESSAGE s100(zbdc).
  cl_gui_cfw=>flush( ).

  DO 2 TIMES.
    lv_attempt = sy-index.
    CLEAR: lo_client, lv_http_code, lv_send_rc, lv_receive_rc.

    cl_http_client=>create_by_url(
      EXPORTING
        url    = lv_readiness_url
      IMPORTING
        client = lo_client
      EXCEPTIONS
        OTHERS = 1 ).

    IF sy-subrc = 0 AND lo_client IS BOUND.
      lo_client->propertytype_redirect = lo_client->co_enabled.
      lo_client->request->set_method( 'GET' ).
      lo_client->request->set_header_field(
        name  = 'Accept'
        value = 'application/json' ).

      lo_client->send(
        EXPORTING
          timeout = lv_timeout
        EXCEPTIONS
          OTHERS = 1 ).
      lv_send_rc = sy-subrc.

      IF lv_send_rc = 0.
        lo_client->receive( EXCEPTIONS OTHERS = 1 ).
        lv_receive_rc = sy-subrc.
      ELSE.
        lv_receive_rc = 99.
      ENDIF.

      IF lv_send_rc = 0 AND lv_receive_rc = 0.
        lo_client->response->get_status(
          IMPORTING
            code = lv_http_code ).
      ENDIF.

      lo_client->close( ).
    ENDIF.

    IF lv_send_rc = 0
    AND lv_receive_rc = 0
    AND lv_http_code >= 200
    AND lv_http_code < 400.
      cv_ok = abap_true.
      cv_message = |n8n readiness check succeeded on attempt { lv_attempt }.|.
      RETURN.
    ENDIF.

    IF lv_attempt < 2.
      WAIT UP TO 5 SECONDS.
    ENDIF.
  ENDDO.

  IF lv_http_code > 0.
    cv_message =
      |n8n readiness check failed with HTTP { lv_http_code }. Direct WF4 call will still be attempted.|.
  ELSEIF lv_send_rc <> 0.
    cv_message =
      |n8n readiness send failed (RC { lv_send_rc }). Direct WF4 call will still be attempted.|.
  ELSEIF lv_receive_rc <> 0.
    cv_message =
      |n8n readiness receive failed (RC { lv_receive_rc }). Direct WF4 call will still be attempted.|.
  ELSE.
    cv_message =
      'n8n readiness check failed. Direct WF4 call will still be attempted.'.
  ENDIF.
ENDFORM.

FORM get_gmail_pull_limit
  CHANGING cv_limit   TYPE i
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_text  TYPE string,
        lv_limit TYPE i.

  CLEAR: cv_limit, cv_ok, cv_message.

  PERFORM get_config_value
    USING    'N8N_GMAIL_PULL_LIMIT'
    CHANGING lv_text.

 "The pull limit is an optional operational policy. Its only default is
 "declared here; malformed configured values are never silently replaced.
  IF lv_text IS INITIAL.
    cv_limit = 100.
    cv_ok = abap_true.
    RETURN.
  ENDIF.

  CONDENSE lv_text NO-GAPS.
  TRY.
      lv_limit = CONV i( lv_text ).
    CATCH cx_sy_conversion_no_number.
      cv_message = 'N8N_GMAIL_PULL_LIMIT must be numeric.'.
      RETURN.
  ENDTRY.

  IF lv_limit < 1 OR lv_limit > 500.
    cv_message = 'N8N_GMAIL_PULL_LIMIT must be between 1 and 500.'.
    RETURN.
  ENDIF.

  cv_limit = lv_limit.
  cv_ok = abap_true.
ENDFORM.

FORM get_gmail_pull_timeout
  CHANGING cv_timeout TYPE i
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_text    TYPE string,
        lv_timeout TYPE i.

  CLEAR: cv_timeout, cv_ok, cv_message.

  PERFORM get_config_value
    USING    'N8N_GMAIL_TIMEOUT_SEC'
    CHANGING lv_text.

  IF lv_text IS INITIAL.
    PERFORM get_config_value
      USING    'TIMEOUT'
      CHANGING lv_text.
  ENDIF.

  IF lv_text IS INITIAL AND txtp_timeout > 0.
    lv_timeout = txtp_timeout.
  ELSE.
    CONDENSE lv_text NO-GAPS.
    TRY.
        lv_timeout = CONV i( lv_text ).
      CATCH cx_sy_conversion_no_number.
        cv_message = 'Gmail pull timeout must be numeric.'.
        RETURN.
    ENDTRY.
  ENDIF.

  IF lv_timeout < 1 OR lv_timeout > 600.
    cv_message = 'Gmail pull timeout must be between 1 and 600 seconds.'.
    RETURN.
  ENDIF.

  cv_timeout = lv_timeout.
  cv_ok = abap_true.
ENDFORM.

FORM json_get_named_block
  USING    iv_json  TYPE string
           iv_key   TYPE string
           iv_open  TYPE c
           iv_close TYPE c
  CHANGING cv_block TYPE string
           cv_ok    TYPE abap_bool.

  DATA: lv_pattern    TYPE string,
        lv_key_pos    TYPE i,
        lv_pos        TYPE i,
        lv_start      TYPE i,
        lv_json_len   TYPE i,
        lv_block_len  TYPE i,
        lv_depth      TYPE i,
        lv_char       TYPE c LENGTH 1,
        lv_in_string  TYPE abap_bool,
        lv_escaped    TYPE abap_bool.

  CLEAR: cv_block, cv_ok.

  lv_pattern  = '"' && iv_key && '"'.
  lv_json_len = strlen( iv_json ).

  FIND FIRST OCCURRENCE OF lv_pattern IN iv_json
    MATCH OFFSET lv_key_pos.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  lv_pos = lv_key_pos + strlen( lv_pattern ).

 "Move to the value separator.
  WHILE lv_pos < lv_json_len.
    lv_char = iv_json+lv_pos(1).
    IF lv_char = ':'.
      lv_pos = lv_pos + 1.
      EXIT.
    ENDIF.
    lv_pos = lv_pos + 1.
  ENDWHILE.

 "Move to the requested opening character.
  WHILE lv_pos < lv_json_len.
    lv_char = iv_json+lv_pos(1).
    IF lv_char = iv_open.
      lv_start = lv_pos.
      EXIT.
    ENDIF.
    lv_pos = lv_pos + 1.
  ENDWHILE.

  IF lv_pos >= lv_json_len OR lv_start < 0.
    RETURN.
  ENDIF.

  CLEAR: lv_depth, lv_in_string, lv_escaped.

  WHILE lv_pos < lv_json_len.
    lv_char = iv_json+lv_pos(1).

    IF lv_in_string = abap_true.
      IF lv_escaped = abap_true.
        lv_escaped = abap_false.
      ELSEIF lv_char = '\'.
        lv_escaped = abap_true.
      ELSEIF lv_char = '"'.
        lv_in_string = abap_false.
      ENDIF.
    ELSE.
      IF lv_char = '"'.
        lv_in_string = abap_true.
      ELSEIF lv_char = iv_open.
        lv_depth = lv_depth + 1.
      ELSEIF lv_char = iv_close.
        lv_depth = lv_depth - 1.
        IF lv_depth = 0.
          lv_block_len = lv_pos - lv_start + 1.
          cv_block = iv_json+lv_start(lv_block_len).
          cv_ok = abap_true.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    lv_pos = lv_pos + 1.
  ENDWHILE.
ENDFORM.

FORM json_split_objects
  USING    iv_json TYPE string
  CHANGING ct_objects TYPE string_table.

  DATA: lv_pos        TYPE i,
        lv_start      TYPE i,
        lv_json_len   TYPE i,
        lv_obj_len    TYPE i,
        lv_depth      TYPE i,
        lv_char       TYPE c LENGTH 1,
        lv_in_string  TYPE abap_bool,
        lv_escaped    TYPE abap_bool,
        lv_object     TYPE string.

  REFRESH ct_objects.
  lv_json_len = strlen( iv_json ).
  lv_start = -1.

  WHILE lv_pos < lv_json_len.
    lv_char = iv_json+lv_pos(1).

    IF lv_in_string = abap_true.
      IF lv_escaped = abap_true.
        lv_escaped = abap_false.
      ELSEIF lv_char = '\'.
        lv_escaped = abap_true.
      ELSEIF lv_char = '"'.
        lv_in_string = abap_false.
      ENDIF.
    ELSE.
      IF lv_char = '"'.
        lv_in_string = abap_true.
      ELSEIF lv_char = '{'.
        IF lv_depth = 0.
          lv_start = lv_pos.
        ENDIF.
        lv_depth = lv_depth + 1.
      ELSEIF lv_char = '}'.
        IF lv_depth > 0.
          lv_depth = lv_depth - 1.
          IF lv_depth = 0 AND lv_start >= 0.
            lv_obj_len = lv_pos - lv_start + 1.
            lv_object = iv_json+lv_start(lv_obj_len).
            APPEND lv_object TO ct_objects.
            lv_start = -1.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

    lv_pos = lv_pos + 1.
  ENDWHILE.
ENDFORM.

FORM parse_gmail_pull_response
  USING    iv_json TYPE string
  CHANGING ct_submissions TYPE ty_t_m1_gmail_submission
           cv_ok          TYPE abap_bool
           cv_message     TYPE string.

  DATA: lv_status         TYPE string,
        lv_error_code     TYPE string,
        lv_api_message    TYPE string,
        lv_submissions    TYPE string,
        lv_contract       TYPE string,
        lv_rows           TYPE string,
        lv_block_ok       TYPE abap_bool,
        lt_objects        TYPE string_table,
        lt_rows           TYPE string_table,
        lv_object         TYPE string,
        ls_submission     TYPE ty_m1_gmail_submission,
        lv_row_count_text TYPE string,
        lv_json_value     TYPE string.

  CLEAR: ct_submissions, cv_ok, cv_message.

  PERFORM json_get_bup USING iv_json 'status' CHANGING lv_status.
  PERFORM json_get_bup USING iv_json 'errorCode' CHANGING lv_error_code.
  PERFORM json_get_bup USING iv_json 'message' CHANGING lv_api_message.

  TRANSLATE lv_status TO UPPER CASE.
  CONDENSE lv_status.

  IF lv_status = 'NO_PENDING_SUBMISSIONS'.
    cv_ok = abap_true.
    cv_message = lv_api_message.
    IF cv_message IS INITIAL.
      cv_message = 'No pending Gmail submissions were found.'.
    ENDIF.
    RETURN.
  ENDIF.

  IF lv_status <> 'PENDING_SUBMISSIONS_FOUND'.
    IF lv_api_message IS INITIAL.
      lv_api_message = |Unexpected Gmail pull status { lv_status }.|.
    ENDIF.
    IF lv_error_code IS NOT INITIAL.
      cv_message = |{ lv_error_code }: { lv_api_message }|.
    ELSE.
      cv_message = lv_api_message.
    ENDIF.
    RETURN.
  ENDIF.

  PERFORM json_get_named_block
    USING    iv_json 'submissions' '[' ']'
    CHANGING lv_submissions lv_block_ok.

  IF lv_block_ok <> abap_true.
    cv_message = 'Gmail pull response is missing submissions array.'.
    RETURN.
  ENDIF.

  PERFORM json_split_objects
    USING    lv_submissions
    CHANGING lt_objects.

  LOOP AT lt_objects INTO lv_object.
    CLEAR: ls_submission,
           lv_contract,
           lv_rows,
           lv_row_count_text,
           lv_json_value,
           lv_block_ok,
           lt_rows.

    CLEAR lv_json_value.
    PERFORM json_get_bup USING lv_object 'submissionId'
      CHANGING lv_json_value.
    ls_submission-submission_id = lv_json_value.

    CLEAR lv_json_value.
    PERFORM json_get_bup USING lv_object 'requestId'
      CHANGING lv_json_value.
    ls_submission-request_id = lv_json_value.

    PERFORM json_get_bup USING lv_object 'rowCount'
      CHANGING lv_row_count_text.

    CLEAR lv_json_value.
    PERFORM json_get_bup USING lv_object 'submittedAt'
      CHANGING lv_json_value.
    ls_submission-submitted_at = lv_json_value.

    CLEAR lv_json_value.
    PERFORM json_get_bup USING lv_object 'status'
      CHANGING lv_json_value.
    ls_submission-status = lv_json_value.

    CLEAR lv_json_value.
    PERFORM json_get_bup USING lv_object 'source'
      CHANGING lv_json_value.
    ls_submission-source = lv_json_value.

    PERFORM json_get_named_block
      USING    lv_object 'contract' '{' '}'
      CHANGING lv_contract lv_block_ok.

    IF lv_block_ok = abap_true.
      CLEAR lv_json_value.
      PERFORM json_get_bup USING lv_contract 'tcode'
        CHANGING lv_json_value.
      ls_submission-tcode = lv_json_value.

      CLEAR lv_json_value.
      PERFORM json_get_bup USING lv_contract 'profile'
        CHANGING lv_json_value.
      ls_submission-profile = lv_json_value.

      CLEAR lv_json_value.
      PERFORM json_get_bup USING lv_contract 'version'
        CHANGING lv_json_value.
      ls_submission-version = lv_json_value.
    ENDIF.

    CLEAR lv_block_ok.
    PERFORM json_get_named_block
      USING    lv_object 'rows' '[' ']'
      CHANGING lv_rows lv_block_ok.

    IF lv_block_ok = abap_true.
      ls_submission-rows_json = lv_rows.
      PERFORM json_split_objects
        USING    lv_rows
        CHANGING lt_rows.
      ls_submission-row_count = lines( lt_rows ).
    ENDIF.

    IF ls_submission-row_count = 0
    AND lv_row_count_text IS NOT INITIAL.
      TRY.
          ls_submission-row_count = CONV i( lv_row_count_text ).
        CATCH cx_sy_conversion_no_number.
          CLEAR ls_submission-row_count.
      ENDTRY.
    ENDIF.

    TRANSLATE ls_submission-tcode TO UPPER CASE.
    TRANSLATE ls_submission-status TO UPPER CASE.
    CONDENSE: ls_submission-submission_id,
              ls_submission-request_id,
              ls_submission-tcode,
              ls_submission-profile,
              ls_submission-version,
              ls_submission-status,
              ls_submission-source.

    IF ls_submission-submission_id IS INITIAL
    OR ls_submission-request_id IS INITIAL
    OR ls_submission-tcode IS INITIAL
    OR ls_submission-profile IS INITIAL
    OR ls_submission-version IS INITIAL
    OR ls_submission-row_count <= 0
    OR ls_submission-rows_json IS INITIAL.
      CONTINUE.
    ENDIF.

    IF ls_submission-status IS NOT INITIAL
    AND ls_submission-status <> 'VALIDATED_PENDING_SAP'.
      CONTINUE.
    ENDIF.

    APPEND ls_submission TO ct_submissions.
  ENDLOOP.

  cv_ok = abap_true.
  cv_message = |{ lines( ct_submissions ) } pending Gmail submission(s) parsed.|.
ENDFORM.

FORM pull_gmail_pending
  CHANGING ct_submissions TYPE ty_t_m1_gmail_submission
           cv_ok          TYPE abap_bool
           cv_message     TYPE string.

  TYPES: BEGIN OF ty_pull_request,
           action     TYPE string,
           request_id TYPE string,
           limit      TYPE i,
         END OF ty_pull_request.

  DATA: lo_client        TYPE REF TO if_http_client,
        ls_request       TYPE ty_pull_request,
        lv_url           TYPE string,
        lv_url_ok        TYPE abap_bool,
        lv_header_name   TYPE string,
        lv_header_value  TYPE string,
        lv_header_ok     TYPE abap_bool,
        lv_timeout       TYPE i,
        lv_body          TYPE string,
        lv_response      TYPE string,
        lv_response_text TYPE string,
        lv_http_code     TYPE i,
        lv_create_rc     TYPE sy-subrc,
        lv_send_rc       TYPE sy-subrc,
        lv_receive_rc    TYPE sy-subrc,
        lv_limit         TYPE i,
        lv_limit_ok      TYPE abap_bool,
        lv_limit_msg     TYPE string,
        lv_timeout_ok    TYPE abap_bool,
        lv_timeout_msg   TYPE string,
        lv_uuid          TYPE string,
        lv_parse_ok      TYPE abap_bool,
        lv_parse_msg     TYPE string,
        lv_api_error     TYPE string,
        lv_api_message   TYPE string,
        lv_wake_ok       TYPE abap_bool,
        lv_wake_message  TYPE string,
        lv_attempt       TYPE i,
        lv_retryable     TYPE abap_bool.

  CLEAR: ct_submissions, cv_ok, cv_message.

  PERFORM get_gmail_pull_url
    CHANGING lv_url lv_url_ok.

  IF lv_url_ok <> abap_true.
    cv_message =
      'WF4 URL is unavailable. Maintain N8N_GMAIL_PULL_URL or N8N_GMAIL_REQUEST_URL.'.
    RETURN.
  ENDIF.

  PERFORM get_gmail_header
    CHANGING lv_header_name lv_header_value lv_header_ok.

  IF lv_header_ok <> abap_true.
    cv_message =
      'Gmail API authentication is unavailable. Check N8N_GMAIL_HEADER_NAME and N8N_GMAIL_HEADER_VALUE.'.
    CLEAR lv_header_value.
    RETURN.
  ENDIF.

  PERFORM get_gmail_pull_timeout
    CHANGING lv_timeout lv_timeout_ok lv_timeout_msg.
  IF lv_timeout_ok <> abap_true.
    cv_message = lv_timeout_msg.
    CLEAR lv_header_value.
    RETURN.
  ENDIF.

  PERFORM get_gmail_pull_limit
    CHANGING lv_limit lv_limit_ok lv_limit_msg.
  IF lv_limit_ok <> abap_true.
    cv_message = lv_limit_msg.
    CLEAR lv_header_value.
    RETURN.
  ENDIF.

  TRY.
      lv_uuid = cl_system_uuid=>create_uuid_c32_static( ).
    CATCH cx_uuid_error.
      PERFORM get_demo_now CHANGING gv_demo_date_837 gv_demo_time_837.
      lv_uuid = |{ gv_demo_date_837 }{ gv_demo_time_837 }|.
  ENDTRY.

  ls_request-action     = 'PULL_PENDING_GMAIL_SUBMISSIONS'.
  ls_request-request_id = |SAP_PULL_{ lv_uuid }|.
  ls_request-limit      = lv_limit.

  TRY.
      lv_body = /ui2/cl_json=>serialize(
        data        = ls_request
        compress    = abap_true
        pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).
    CATCH cx_root INTO DATA(lx_serialize).
      cv_message =
        |Cannot serialize Gmail pull request: { lx_serialize->get_text( ) }|.
      CLEAR lv_header_value.
      RETURN.
  ENDTRY.

 "Wake a sleeping Render/n8n service before the authenticated POST.
 "A failed readiness probe does not hide the real WF4 result; the POST is
 "still attempted and its exact HTTP/communication error is returned.
  PERFORM wake_n8n
    USING    lv_url lv_timeout
    CHANGING lv_wake_ok lv_wake_message.

  DO 2 TIMES.
    lv_attempt = sy-index.

    CLEAR: lo_client,
           lv_response,
           lv_http_code,
           lv_create_rc,
           lv_send_rc,
           lv_receive_rc,
           lv_retryable.

    cl_http_client=>create_by_url(
      EXPORTING
        url    = lv_url
      IMPORTING
        client = lo_client
      EXCEPTIONS
        OTHERS = 1 ).
    lv_create_rc = sy-subrc.

    IF lv_create_rc <> 0 OR lo_client IS INITIAL.
      IF lv_attempt < 2.
        WAIT UP TO 5 SECONDS.
        CONTINUE.
      ENDIF.

      cv_message =
        |Cannot create HTTPS client for WF4 (RC { lv_create_rc }). Check URL and STRUST SSL client trust.|.
      IF lv_wake_message IS NOT INITIAL.
        cv_message = |{ cv_message } { lv_wake_message }|.
      ENDIF.
      CLEAR lv_header_value.
      RETURN.
    ENDIF.

    lo_client->propertytype_redirect = lo_client->co_enabled.
    lo_client->request->set_method( 'POST' ).
    lo_client->request->set_header_field(
      name  = 'Content-Type'
      value = 'application/json; charset=utf-8' ).
    lo_client->request->set_header_field(
      name  = 'Accept'
      value = 'application/json' ).
 "stable style DB-backed Header Auth. The shared helper
 "fails closed when name/value is unavailable; always send the exact pair.
    lo_client->request->set_header_field(
      name  = lv_header_name
      value = lv_header_value ).
    lo_client->request->set_header_field(
      name  = 'X-SAP-BDC-Request-ID'
      value = ls_request-request_id ).
    lo_client->request->set_cdata( lv_body ).

    lo_client->send(
      EXPORTING
        timeout = lv_timeout
      EXCEPTIONS
        OTHERS = 1 ).
    lv_send_rc = sy-subrc.

    IF lv_send_rc = 0.
      lo_client->receive( EXCEPTIONS OTHERS = 1 ).
      lv_receive_rc = sy-subrc.
    ELSE.
      lv_receive_rc = 99.
    ENDIF.

    IF lv_send_rc = 0 AND lv_receive_rc = 0.
      lo_client->response->get_status(
        IMPORTING
          code = lv_http_code ).
      lv_response = lo_client->response->get_cdata( ).
    ENDIF.

    lo_client->close( ).

    IF lv_send_rc <> 0 OR lv_receive_rc <> 0.
      IF lv_attempt < 2.
        WAIT UP TO 5 SECONDS.
        CONTINUE.
      ENDIF.

      IF lv_send_rc <> 0.
        cv_message =
          |WF4 send failed after { lv_attempt } attempt(s), RC { lv_send_rc }.|.
      ELSE.
        cv_message =
          |WF4 receive failed after { lv_attempt } attempt(s), RC { lv_receive_rc }.|.
      ENDIF.

      IF lv_wake_message IS NOT INITIAL.
        cv_message = |{ cv_message } { lv_wake_message }|.
      ENDIF.

      CLEAR lv_header_value.
      RETURN.
    ENDIF.

    IF lv_http_code >= 200 AND lv_http_code < 300.
      EXIT.
    ENDIF.

    IF lv_http_code = 408
    OR lv_http_code = 425
    OR lv_http_code = 429
    OR lv_http_code = 502
    OR lv_http_code = 503
    OR lv_http_code = 504.
      lv_retryable = abap_true.
    ENDIF.

    IF lv_retryable = abap_true AND lv_attempt < 2.
      WAIT UP TO 5 SECONDS.
      CONTINUE.
    ENDIF.

    EXIT.
  ENDDO.

  CLEAR lv_header_value.

  IF lv_http_code < 200 OR lv_http_code >= 300.
    CLEAR: lv_api_error, lv_api_message, lv_response_text.

    PERFORM json_get_bup
      USING    lv_response 'errorCode'
      CHANGING lv_api_error.

    PERFORM json_get_bup
      USING    lv_response 'message'
      CHANGING lv_api_message.

    IF lv_http_code = 401 OR lv_http_code = 403.
      cv_message =
        |WF4 authorization failed (HTTP { lv_http_code }). Check the SAP Header Auth value against n8n.|.
      RETURN.
    ELSEIF lv_http_code = 404.
      cv_message =
        |WF4 endpoint not found (HTTP 404). Resolved URL: { lv_url }|.
      RETURN.
    ENDIF.

    IF lv_api_message IS NOT INITIAL.
      IF lv_api_error IS NOT INITIAL.
        cv_message =
          |WF4 HTTP { lv_http_code } - { lv_api_error }: { lv_api_message }|.
      ELSE.
        cv_message =
          |WF4 HTTP { lv_http_code }: { lv_api_message }|.
      ENDIF.
      RETURN.
    ENDIF.

    lv_response_text = lv_response.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
      IN lv_response_text WITH space.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline
      IN lv_response_text WITH space.
    CONDENSE lv_response_text.

    IF strlen( lv_response_text ) > 180.
      lv_response_text = lv_response_text(180).
    ENDIF.

    IF lv_response_text IS INITIAL.
      cv_message =
        |WF4 returned HTTP { lv_http_code } without a JSON error body.|.
    ELSE.
      cv_message =
        |WF4 returned HTTP { lv_http_code }: { lv_response_text }|.
    ENDIF.
    RETURN.
  ENDIF.

  IF lv_response IS INITIAL.
    cv_message = 'WF4 returned HTTP success but the response body is empty.'.
    RETURN.
  ENDIF.

  PERFORM parse_gmail_pull_response
    USING    lv_response
    CHANGING ct_submissions lv_parse_ok lv_parse_msg.

  cv_message = lv_parse_msg.
  cv_ok      = lv_parse_ok.
ENDFORM.

FORM select_gmail_submissions
  USING    it_submissions TYPE ty_t_m1_gmail_submission
  CHANGING ct_selected    TYPE ty_t_m1_gmail_submission
           cv_canceled    TYPE abap_bool.

  DATA: lt_popup      TYPE ty_t_m1_gmail_popup,
        ls_popup      TYPE ty_m1_gmail_popup,
        lt_fieldcat   TYPE slis_t_fieldcat_alv,
        ls_fieldcat   TYPE slis_fieldcat_alv,
        ls_selfield   TYPE slis_selfield,
        lv_exit       TYPE c,
        lv_seq        TYPE i,
        lv_seq_text   TYPE c LENGTH 4,
        ls_submission TYPE ty_m1_gmail_submission.

  CLEAR: ct_selected, cv_canceled.

  LOOP AT it_submissions INTO ls_submission.
    lv_seq = lv_seq + 1.
    CLEAR: ls_popup, lv_seq_text.
    WRITE lv_seq TO lv_seq_text LEFT-JUSTIFIED.
    CONDENSE lv_seq_text NO-GAPS.

    ls_popup-sel_no        = lv_seq_text.
    ls_popup-request_id    = ls_submission-request_id.
    ls_popup-tcode         = ls_submission-tcode.
    ls_popup-profile       = ls_submission-profile.
    ls_popup-version       = ls_submission-version.
    ls_popup-row_count     = ls_submission-row_count.
    ls_popup-submitted_at  = ls_submission-submitted_at.
    ls_popup-submission_id = ls_submission-submission_id.
    APPEND ls_popup TO lt_popup.
  ENDLOOP.

  IF lt_popup IS INITIAL.
    RETURN.
  ENDIF.

  DEFINE add_z199_fcat.
    CLEAR ls_fieldcat.
    ls_fieldcat-fieldname = &1.
    ls_fieldcat-seltext_s = &2.
    ls_fieldcat-seltext_m = &3.
    ls_fieldcat-seltext_l = &3.
    ls_fieldcat-outputlen = &4.
    ls_fieldcat-no_out    = &5.
    APPEND ls_fieldcat TO lt_fieldcat.
  END-OF-DEFINITION.

  add_z199_fcat 'SEL_NO'        'No'      'No'             4  ''.
  add_z199_fcat 'REQUEST_ID'     'Request' 'Request ID'     42 ''.
  add_z199_fcat 'TCODE'          'TCODE'   'Transaction'    12 ''.
  add_z199_fcat 'PROFILE'        'Profile' 'Profile'        26 ''.
  add_z199_fcat 'VERSION'        'Version' 'Version'        10 ''.
  add_z199_fcat 'ROW_COUNT'      'Rows'    'Rows'            8 ''.
  add_z199_fcat 'SUBMITTED_AT'   'Time'    'Submitted At'   24 ''.
  add_z199_fcat 'SUBMISSION_ID'  'ID'      'Submission ID'  10 'X'.

  CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
    EXPORTING
      i_title               = 'Gmail Data Entry Submissions'
      i_selection           = 'X'
      i_zebra               = 'X'
      i_checkbox_fieldname  = 'MARK'
      i_tabname             = 'LT_POPUP'
      it_fieldcat           = lt_fieldcat
      i_screen_start_column = 4
      i_screen_start_line   = 2
      i_screen_end_column   = 128
      i_screen_end_line     = 24
    IMPORTING
      es_selfield           = ls_selfield
      e_exit                = lv_exit
    TABLES
      t_outtab              = lt_popup
    EXCEPTIONS
      program_error         = 1
      OTHERS                = 2.

  IF lv_exit = 'X' OR sy-subrc <> 0.
    cv_canceled = abap_true.
    RETURN.
  ENDIF.

  LOOP AT lt_popup INTO ls_popup WHERE mark = 'X'.
    READ TABLE it_submissions INTO ls_submission
      WITH KEY submission_id = ls_popup-submission_id.
    IF sy-subrc = 0.
      APPEND ls_submission TO ct_selected.
    ENDIF.
  ENDLOOP.

 "Double-click or cursor selection is accepted as a single selection.
  IF ct_selected IS INITIAL AND ls_selfield-tabindex IS NOT INITIAL.
    READ TABLE lt_popup INTO ls_popup INDEX ls_selfield-tabindex.
    IF sy-subrc = 0.
      READ TABLE it_submissions INTO ls_submission
        WITH KEY submission_id = ls_popup-submission_id.
      IF sy-subrc = 0.
        APPEND ls_submission TO ct_selected.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

FORM gmail_skip_json_ws
  USING    iv_json TYPE string
  CHANGING cv_pos  TYPE i.

  DATA: lv_len  TYPE i,
        lv_char TYPE c LENGTH 1,
        lv_cr   TYPE c LENGTH 1.

  lv_len = strlen( iv_json ).
  lv_cr = cl_abap_char_utilities=>cr_lf.

  WHILE cv_pos < lv_len.
    lv_char = iv_json+cv_pos(1).
    IF lv_char = space
    OR lv_char = cl_abap_char_utilities=>horizontal_tab
    OR lv_char = cl_abap_char_utilities=>newline
    OR lv_char = lv_cr.
      cv_pos = cv_pos + 1.
    ELSE.
      EXIT.
    ENDIF.
  ENDWHILE.
ENDFORM.

FORM gmail_parse_row_exact
  USING    iv_obj     TYPE string
  CHANGING ct_keys    TYPE string_table
           ct_vals    TYPE string_table
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_pos       TYPE i,
        lv_len       TYPE i,
        lv_start     TYPE i,
        lv_token_len TYPE i,
        lv_char      TYPE c LENGTH 1,
        lv_escape    TYPE c LENGTH 1,
        lv_first     TYPE c LENGTH 1,
        lv_key       TYPE string,
        lv_key_upper TYPE string,
        lv_value     TYPE string,
        lv_closed    TYPE abap_bool,
        lv_done      TYPE abap_bool,
        lt_seen      TYPE SORTED TABLE OF string WITH UNIQUE KEY table_line.

  CLEAR: cv_ok, cv_message.
  REFRESH: ct_keys, ct_vals.

  lv_len = strlen( iv_obj ).
  IF lv_len = 0.
    cv_message = 'GMAIL_ROW_JSON_EMPTY: submitted row object is empty.'.
    RETURN.
  ENDIF.

  PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.
  IF lv_pos >= lv_len.
    cv_message = 'GMAIL_ROW_JSON_EMPTY: submitted row object is empty.'.
    RETURN.
  ENDIF.

  lv_char = iv_obj+lv_pos(1).
  IF lv_char <> '{'.
    cv_message = 'GMAIL_ROW_JSON_INVALID: row must be a flat JSON object.'.
    RETURN.
  ENDIF.
  lv_pos = lv_pos + 1.

  WHILE lv_pos < lv_len AND lv_done <> abap_true.
    PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.
    IF lv_pos >= lv_len.
      EXIT.
    ENDIF.

    lv_char = iv_obj+lv_pos(1).
    IF lv_char = '}'.
      lv_done = abap_true.
      lv_pos = lv_pos + 1.
      EXIT.
    ENDIF.

    IF lv_char <> '"'.
      cv_message = |GMAIL_ROW_JSON_INVALID: expected field name at offset { lv_pos }.|.
      RETURN.
    ENDIF.

    lv_pos = lv_pos + 1.
    CLEAR: lv_key, lv_closed.
    WHILE lv_pos < lv_len.
      lv_char = iv_obj+lv_pos(1).
      IF lv_char = '"'.
        lv_closed = abap_true.
        lv_pos = lv_pos + 1.
        EXIT.
      ELSEIF lv_char = '\'.
        cv_message = 'GMAIL_ROW_KEY_INVALID: escaped JSON field names are not accepted.'.
        RETURN.
      ELSE.
        lv_key = lv_key && lv_char.
        lv_pos = lv_pos + 1.
      ENDIF.
    ENDWHILE.

    IF lv_closed <> abap_true OR lv_key IS INITIAL.
      cv_message = 'GMAIL_ROW_KEY_INVALID: field name is empty or unterminated.'.
      RETURN.
    ENDIF.

    lv_key_upper = lv_key.
    TRANSLATE lv_key_upper TO UPPER CASE.
    IF lv_key <> lv_key_upper.
      cv_message = |GMAIL_ROW_KEY_INVALID: field { lv_key } is not the exact normalized source name.|.
      RETURN.
    ENDIF.

    lv_first = lv_key+0(1).
    IF lv_first CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    OR lv_key CN 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.
      cv_message = |GMAIL_ROW_KEY_INVALID: field { lv_key } is not a valid dynamic-form source name.|.
      RETURN.
    ENDIF.

    READ TABLE lt_seen WITH TABLE KEY table_line = lv_key TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      cv_message = |GMAIL_ROW_KEY_DUPLICATE: field { lv_key } occurs more than once.|.
      RETURN.
    ENDIF.
    INSERT lv_key INTO TABLE lt_seen.

    PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.
    IF lv_pos >= lv_len OR iv_obj+lv_pos(1) <> ':'.
      cv_message = |GMAIL_ROW_JSON_INVALID: field { lv_key } has no value separator.|.
      RETURN.
    ENDIF.
    lv_pos = lv_pos + 1.
    PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.

    IF lv_pos >= lv_len.
      cv_message = |GMAIL_ROW_JSON_INVALID: field { lv_key } has no value.|.
      RETURN.
    ENDIF.

    CLEAR: lv_value, lv_closed.
    lv_char = iv_obj+lv_pos(1).

    IF lv_char = '"'.
      lv_pos = lv_pos + 1.
      WHILE lv_pos < lv_len.
        lv_char = iv_obj+lv_pos(1).
        IF lv_char = '"'.
          lv_closed = abap_true.
          lv_pos = lv_pos + 1.
          EXIT.
        ELSEIF lv_char = '\'.
          lv_pos = lv_pos + 1.
          IF lv_pos >= lv_len.
            cv_message = |GMAIL_ROW_JSON_INVALID: field { lv_key } ends in an incomplete escape.|.
            RETURN.
          ENDIF.
          lv_escape = iv_obj+lv_pos(1).
          CASE lv_escape.
            WHEN '"' OR '\' OR '/'.
              lv_value = lv_value && lv_escape.
            WHEN OTHERS.
              cv_message = |GMAIL_ROW_ESCAPE_UNSUPPORTED: field { lv_key } contains escape \\{ lv_escape }; source value was not staged.|.
              RETURN.
          ENDCASE.
          lv_pos = lv_pos + 1.
        ELSE.
          lv_value = lv_value && lv_char.
          lv_pos = lv_pos + 1.
        ENDIF.
      ENDWHILE.

      IF lv_closed <> abap_true.
        cv_message = |GMAIL_ROW_JSON_INVALID: value for field { lv_key } is unterminated.|.
        RETURN.
      ENDIF.
    ELSE.
      IF lv_char = '{' OR lv_char = '['.
        cv_message = |GMAIL_ROW_VALUE_NESTED: field { lv_key } must be a scalar value.|.
        RETURN.
      ENDIF.

      lv_start = lv_pos.
      WHILE lv_pos < lv_len.
        lv_char = iv_obj+lv_pos(1).
        IF lv_char = ',' OR lv_char = '}'.
          EXIT.
        ENDIF.
        lv_pos = lv_pos + 1.
      ENDWHILE.
      lv_token_len = lv_pos - lv_start.
      IF lv_token_len > 0.
        lv_value = iv_obj+lv_start(lv_token_len).
        CONDENSE lv_value.
        IF lv_value = 'null'.
          CLEAR lv_value.
        ENDIF.
      ENDIF.
    ENDIF.

    APPEND lv_key TO ct_keys.
    APPEND lv_value TO ct_vals.

    IF lines( ct_keys ) > 25.
      cv_message = 'GMAIL_SCHEMA_TOO_WIDE: Preview/Staging supports at most 25 source columns.'.
      RETURN.
    ENDIF.

    PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.
    IF lv_pos >= lv_len.
      EXIT.
    ENDIF.

    lv_char = iv_obj+lv_pos(1).
    IF lv_char = ','.
      lv_pos = lv_pos + 1.
      CONTINUE.
    ELSEIF lv_char = '}'.
      lv_done = abap_true.
      lv_pos = lv_pos + 1.
      EXIT.
    ELSE.
      cv_message = |GMAIL_ROW_JSON_INVALID: unexpected token after field { lv_key }.|.
      RETURN.
    ENDIF.
  ENDWHILE.

  PERFORM gmail_skip_json_ws USING iv_obj CHANGING lv_pos.
  IF lv_done <> abap_true OR lv_pos < lv_len.
    cv_message = 'GMAIL_ROW_JSON_INVALID: row object has trailing or incomplete JSON content.'.
    RETURN.
  ENDIF.

  IF ct_keys IS INITIAL OR lines( ct_keys ) <> lines( ct_vals ).
    cv_message = 'GMAIL_ROW_JSON_INVALID: no complete source fields were parsed.'.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM gmail_resolve_schema
  USING    it_actual   TYPE string_table
  CHANGING ct_schema   TYPE string_table
           cv_ok       TYPE abap_bool
           cv_message  TYPE string.

  DATA: lt_manifest TYPE string_table,
        lv_found    TYPE abap_bool,
        lv_load_ok  TYPE abap_bool,
        lv_load_msg TYPE string,
        lv_name     TYPE string,
        lv_tcode    TYPE zbdc_prof_bup-tcode,
        lv_profile  TYPE zbdc_prof_bup-profile_name,
        lv_ver      TYPE zbdc_prof_bup-profile_ver.

  CLEAR: cv_ok, cv_message.
  REFRESH: ct_schema, lt_manifest.

  IF it_actual IS INITIAL.
    cv_message = 'GMAIL_SCHEMA_EMPTY: submitted row contains no source fields.'.
    RETURN.
  ENDIF.

  "The screen display field TXTP_PROFILE_NAME is CHAR50, while the shared
  "manifest loader is deliberately typed to the DDIC profile identity. Copy
  "the current screen context into exact DDIC-typed locals before PERFORM so
  "older ABAP kernels do not reject the actual/formal parameter types.
  lv_tcode   = p_transaction.
  lv_profile = txtp_profile_name.
  lv_ver     = gv_profile_ver.

  PERFORM load_template_manifest
    USING    lv_tcode lv_profile lv_ver
    CHANGING lt_manifest lv_found lv_load_ok lv_load_msg.

  IF lv_load_ok <> abap_true.
    cv_message = |GMAIL_SCHEMA_MANIFEST_INVALID: { lv_load_msg }|.
    RETURN.
  ENDIF.

  IF lv_found = abap_true.
    LOOP AT lt_manifest INTO lv_name.
      READ TABLE it_actual WITH KEY table_line = lv_name TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        cv_message = |GMAIL_SCHEMA_MISMATCH: submitted data is missing frozen source column { lv_name }. Regenerate the Gmail form for this exact profile/version.|.
        RETURN.
      ENDIF.
    ENDLOOP.

    LOOP AT it_actual INTO lv_name.
      READ TABLE lt_manifest WITH KEY table_line = lv_name TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        cv_message = |GMAIL_SCHEMA_MISMATCH: submitted data contains unexpected source column { lv_name }. Regenerate the Gmail form for this exact profile/version.|.
        RETURN.
      ENDIF.
    ENDLOOP.

    IF lines( lt_manifest ) <> lines( it_actual ).
      cv_message = |GMAIL_SCHEMA_MISMATCH: submitted column count { lines( it_actual ) } differs from frozen manifest count { lines( lt_manifest ) }.|.
      RETURN.
    ENDIF.

    ct_schema = lt_manifest.
  ELSE.
    "Legacy exact-version profiles may predate the frozen Template manifest.
    "For them, the normalized Gmail row itself is the source schema; the named
    "staging binder below still requires one exact Mapping identity per field.
    ct_schema = it_actual.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

FORM gmail_align_row
  USING    it_schema   TYPE string_table
           it_keys     TYPE string_table
           it_vals     TYPE string_table
  CHANGING ct_vals     TYPE string_table
           cv_ok       TYPE abap_bool
           cv_message  TYPE string.

  DATA: lv_key   TYPE string,
        lv_value TYPE string,
        lv_index TYPE i.

  CLEAR: cv_ok, cv_message.
  REFRESH ct_vals.

  IF lines( it_keys ) <> lines( it_vals ).
    cv_message = 'GMAIL_ROW_SCHEMA_INVALID: key/value count differs.'.
    RETURN.
  ENDIF.

  IF lines( it_schema ) <> lines( it_keys ).
    cv_message = |GMAIL_ROW_SCHEMA_MISMATCH: row has { lines( it_keys ) } columns; expected { lines( it_schema ) }.|.
    RETURN.
  ENDIF.

  LOOP AT it_schema INTO lv_key.
    READ TABLE it_keys WITH KEY table_line = lv_key TRANSPORTING NO FIELDS.
    IF sy-subrc <> 0.
      cv_message = |GMAIL_ROW_SCHEMA_MISMATCH: row is missing source column { lv_key }.|.
      RETURN.
    ENDIF.
    lv_index = sy-tabix.
    CLEAR lv_value.
    READ TABLE it_vals INTO lv_value INDEX lv_index.
    IF sy-subrc <> 0.
      cv_message = |GMAIL_ROW_SCHEMA_MISMATCH: value for source column { lv_key } is missing.|.
      RETURN.
    ENDIF.
    APPEND lv_value TO ct_vals.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM cache_gmail_preview_schema
  USING    it_headers    TYPE string_table
           iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_ok         TYPE abap_bool.

  DATA: ls_hdr    TYPE ty_preview_hdr_cache,
        lv_header TYPE string,
        lv_col_no TYPE i.

  CLEAR cv_ok.
  DELETE gt_preview_hdr_cache WHERE session_id = iv_session_id.

  IF it_headers IS INITIAL.
    gv_ingest_error_msg = 'GMAIL_PREVIEW_SCHEMA_EMPTY: no exact source headers were parsed.'.
    RETURN.
  ENDIF.

  LOOP AT it_headers INTO lv_header.
    lv_col_no = sy-tabix.
    IF lv_col_no > 25.
      DELETE gt_preview_hdr_cache WHERE session_id = iv_session_id.
      gv_ingest_error_msg =
        |GMAIL_PREVIEW_SCHEMA_TOO_WIDE: source has more than 25 business columns.|.
      RETURN.
    ENDIF.

    CLEAR ls_hdr.
    ls_hdr-session_id  = iv_session_id.
    ls_hdr-col_no      = lv_col_no.
    ls_hdr-header_text = lv_header.
    APPEND ls_hdr TO gt_preview_hdr_cache.
  ENDLOOP.

  cv_ok = abap_true.
ENDFORM.

FORM cache_gmail_preview_row
  USING    it_cols       TYPE string_table
           iv_session_id TYPE zbdc_staging_bup-session_id
           iv_row_index  TYPE i
  CHANGING cv_ok         TYPE abap_bool.

  DATA: ls_cache TYPE ty_preview_src_cache,
        lv_value TYPE string,
        lv_col_no TYPE i,
        lv_nr TYPE n LENGTH 2,
        lv_component TYPE string.
  FIELD-SYMBOLS <lv_preview> TYPE any.

  CLEAR cv_ok.
  IF lines( it_cols ) > 25.
    gv_ingest_error_msg =
      |GMAIL_PREVIEW_ROW_TOO_WIDE: row { iv_row_index } has more than 25 business columns.|.
    RETURN.
  ENDIF.

  CLEAR ls_cache.
  ls_cache-session_id = iv_session_id.
  ls_cache-row_index  = iv_row_index.
  ls_cache-preview_row-tx_code   = p_transaction.
  ls_cache-preview_row-excel_row = iv_row_index.

  LOOP AT it_cols INTO lv_value.
    lv_col_no = sy-tabix.
    lv_nr = lv_col_no.
    CONCATENATE 'COL' lv_nr INTO lv_component.

    UNASSIGN <lv_preview>.
    ASSIGN COMPONENT lv_component
      OF STRUCTURE ls_cache-preview_row TO <lv_preview>.
    IF sy-subrc <> 0 OR <lv_preview> IS NOT ASSIGNED.
      gv_ingest_error_msg =
        |GMAIL_PREVIEW_SLOT_INVALID: { lv_component } is unavailable.|.
      RETURN.
    ENDIF.

    <lv_preview> = lv_value.
    UNASSIGN <lv_preview>.
  ENDLOOP.

  DELETE gt_preview_src_cache
    WHERE session_id = iv_session_id
      AND row_index  = iv_row_index.
  APPEND ls_cache TO gt_preview_src_cache.
  cv_ok = abap_true.
ENDFORM.

FORM browse_gmail_pending.
  DATA: lt_available     TYPE ty_t_m1_gmail_submission,
        lt_selected      TYPE ty_t_m1_gmail_submission,
        ls_selected      TYPE ty_m1_gmail_submission,
        lv_pull_ok       TYPE abap_bool,
        lv_pull_message  TYPE string,
        lv_canceled      TYPE abap_bool,
        lv_scope_tcode   TYPE zbdc_prof_bup-tcode,
        lv_scope_profile TYPE zbdc_prof_bup-profile_name,
        lv_scope_ver     TYPE zbdc_prof_bup-profile_ver,
        lv_selected      TYPE i,
        lv_msg           TYPE string.

  PERFORM pull_gmail_pending
    CHANGING lt_available lv_pull_ok lv_pull_message.

  IF lv_pull_ok <> abap_true.
    IF lv_pull_message IS INITIAL.
      lv_pull_message = 'Gmail pending submission pull failed.'.
    ENDIF.
    MESSAGE lv_pull_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF lt_available IS INITIAL.
    MESSAGE lv_pull_message TYPE 'S' DISPLAY LIKE 'I'.
    RETURN.
  ENDIF.

  PERFORM select_gmail_submissions
    USING    lt_available
    CHANGING lt_selected lv_canceled.

  IF lv_canceled = abap_true.
    MESSAGE s101(zbdc).
    RETURN.
  ENDIF.

  IF lt_selected IS INITIAL.
    MESSAGE s102(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  "One Browse selection must still own one immutable contract. The actual
  "staging/session creation is deliberately deferred until Upload/Ingest.
  CLEAR: lv_scope_tcode, lv_scope_profile, lv_scope_ver.
  LOOP AT lt_selected INTO ls_selected.
    IF lv_scope_tcode IS INITIAL.
      lv_scope_tcode   = ls_selected-tcode.
      lv_scope_profile = ls_selected-profile.
      lv_scope_ver     = ls_selected-version.
    ELSEIF ls_selected-tcode   <> lv_scope_tcode OR
           ls_selected-profile <> lv_scope_profile OR
           ls_selected-version <> lv_scope_ver.
      MESSAGE s103(zbdc) DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDLOOP.

  "A newly selected source invalidates the previous current-upload preview,
  "but does not persist anything yet.
  PERFORM clear_0300_after_browse.
  REFRESH: gt_local_selected_files, gt_m1_gmail_selected_pending.
  CLEAR gv_gdrive_file_id_temp.
  gt_m1_gmail_selected_pending = lt_selected.

  lv_selected = lines( gt_m1_gmail_selected_pending ).
  txtp_file_path = |GmailForm://{ lv_selected } submission(s)|.
  txtp_file_size = '0 B'.
  PERFORM set_row_count_fields USING 0.

  lv_msg = |{ lv_selected } Gmail submission(s) selected. Press Upload/Ingest to create staging data.|.
  MESSAGE lv_msg TYPE 'S'.
ENDFORM.


FORM upload_gmail_pending.

  TYPES: BEGIN OF ty_ingest_audit,
           session_id    TYPE zbdc_staging_bup-session_id,
           submission_id TYPE c LENGTH 100,
           request_id    TYPE c LENGTH 100,
           tcode         TYPE zbdc_prof_bup-tcode,
           profile       TYPE zbdc_prof_bup-profile_name,
           version       TYPE zbdc_prof_bup-profile_ver,
           row_count     TYPE i,
           file_ref      TYPE zbdc_file_lg_bup-file_name,
           submitted_at  TYPE c LENGTH 40,
         END OF ty_ingest_audit.

  DATA: lt_selected       TYPE ty_t_m1_gmail_submission,
        ls_selected       TYPE ty_m1_gmail_submission,
        lt_row_objects    TYPE string_table,
        lv_row_object     TYPE string,
        lt_row_keys       TYPE string_table,
        lt_row_vals       TYPE string_table,
        lt_schema_keys    TYPE string_table,
        lt_cols           TYPE string_table,
        lv_row_ok         TYPE abap_bool,
        lv_row_msg        TYPE string,
        lv_schema_ok      TYPE abap_bool,
        lv_schema_msg     TYPE string,
        lv_align_ok       TYPE abap_bool,
        lv_align_msg      TYPE string,
        lv_session_id     TYPE zbdc_staging_bup-session_id,
        lv_submission_idx TYPE i,
        lv_row_idx        TYPE i,
        lv_before         TYPE i,
        lv_after          TYPE i,
        lv_loaded_total   TYPE i,
        lv_skipped        TYPE i,
        lv_duplicate      TYPE i,
        lv_map_count      TYPE i,
        lv_existing       TYPE i,
        lv_file_ref_text  TYPE string,
        lv_file_ref       TYPE zbdc_file_lg_bup-file_name,
        ls_profile        TYPE zbdc_prof_bup,
        lv_scope_tcode    TYPE zbdc_prof_bup-tcode,
        lv_scope_profile  TYPE zbdc_prof_bup-profile_name,
        lv_scope_ver      TYPE zbdc_prof_bup-profile_ver,
        lt_audit          TYPE STANDARD TABLE OF ty_ingest_audit,
        ls_audit          TYPE ty_ingest_audit,
        ls_meta           TYPE ty_files_disp,
        ls_first_staging  TYPE zbdc_staging_bup,
        lv_ctx_ok         TYPE abap_bool,
        lv_ctx_message    TYPE string,
        lv_audit_count    TYPE i,
        lv_preview_ok     TYPE abap_bool,
        lv_integrity_fail TYPE abap_bool,
        lv_integrity_msg  TYPE string,
        lt_blank_scope    TYPE ty_t_staging_alv,
        ls_blank_row      TYPE ty_staging_alv,
        lv_blank_ok       TYPE abap_bool,
        lv_blank_msg      TYPE string.

  "Upload/Ingest consumes only the exact Gmail selection previously made by
  "Browse. It must never open the source picker itself, otherwise Gmail would
  "bypass the same Browse -> Upload/Ingest -> Preview contract as Local/Drive.
  lt_selected = gt_m1_gmail_selected_pending.
  IF lt_selected IS INITIAL OR txtp_file_path NP 'GmailForm://*'.
    MESSAGE 'Select Gmail submission(s) with Browse first, then press Upload/Ingest.'
      TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

 "One ingestion command owns one immutable contract. Multi-select is allowed
 "only within the same TCODE/Profile/Version; mixed contracts are separate
 "sessions and must be imported in separate commands.
  CLEAR: lv_scope_tcode, lv_scope_profile, lv_scope_ver.
  LOOP AT lt_selected INTO ls_selected.
    IF lv_scope_tcode IS INITIAL.
      lv_scope_tcode   = ls_selected-tcode.
      lv_scope_profile = ls_selected-profile.
      lv_scope_ver     = ls_selected-version.
    ELSEIF ls_selected-tcode   <> lv_scope_tcode OR
           ls_selected-profile <> lv_scope_profile OR
           ls_selected-version <> lv_scope_ver.
    MESSAGE s103(zbdc) DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.
  ENDLOOP.

  PERFORM clear_0300_after_browse.
  REFRESH: gt_staging, gt_staging_alv, gt_errors, gt_preview_data,
           gt_preview_src_cache, gt_preview_hdr_cache.
  PERFORM start_ingest_batch.

  LOOP AT lt_selected INTO ls_selected.
    CLEAR: ls_profile, lv_map_count, lv_existing,
           lv_file_ref_text, lv_file_ref, lt_row_objects,
           lt_row_keys, lt_row_vals, lt_schema_keys, lt_cols.

 "Submission ID is the stable source reference used for duplicate control.
    lv_file_ref_text = |GmailForm://{ ls_selected-submission_id }| &&
                       |?request={ ls_selected-request_id }|.
    lv_file_ref = lv_file_ref_text.

    SELECT COUNT(*)
      FROM zbdc_file_lg_bup
      INTO @lv_existing
      WHERE file_name = @lv_file_ref
        AND source    = 'GMAIL_FORM'
        AND status    = 'IMPORTED'.

    IF lv_existing > 0.
      lv_duplicate = lv_duplicate + 1.
      CONTINUE.
    ENDIF.

 "Gmail submission already carries an exact immutable
 "TCODE/Profile/Version. Preview ingestion may use ACTIVE or TESTING;
 "execution certification remains a separate fail-closed gate.
    SELECT SINGLE *
      FROM zbdc_prof_bup
      INTO @ls_profile
      WHERE tcode        = @ls_selected-tcode
        AND profile_name = @ls_selected-profile
        AND profile_ver  = @ls_selected-version.

    IF sy-subrc <> 0 OR
       ( ls_profile-status <> 'ACTIVE' AND ls_profile-status <> 'TESTING' ).
      lv_skipped = lv_skipped + 1.
      CONTINUE.
    ENDIF.

    SELECT COUNT(*)
      FROM zbdc_mapping_bup
      INTO @lv_map_count
      WHERE tcode        = @ls_selected-tcode
        AND profile_name = @ls_selected-profile
        AND profile_ver  = @ls_selected-version.

    IF lv_map_count <= 0.
      lv_skipped = lv_skipped + 1.
      CONTINUE.
    ENDIF.

    PERFORM json_split_objects
      USING    ls_selected-rows_json
      CHANGING lt_row_objects.

    IF lt_row_objects IS INITIAL.
      lv_skipped = lv_skipped + 1.
      CONTINUE.
    ENDIF.

    p_transaction    = ls_selected-tcode.
    txtp_profile_name = ls_selected-profile.
    gv_profile_ver    = ls_selected-version.

    lv_submission_idx = lv_submission_idx + 1.
    PERFORM make_batch_session
      USING    lv_submission_idx
      CHANGING lv_session_id.

    gv_forced_session_id = lv_session_id.
    gv_current_file_name = lv_file_ref.
    gv_current_sheet_name = 'GMAIL_FORM'.
    gv_current_unit_src = 'GMAIL_FORM'.

    "Gmail must establish the same exact session owner as Local/Drive before
    "actual-data contract validation. ACTIVE freezes Script/Hash; TESTING may
    "persist the exact preview TCODE/Profile/Version owner fail-closed.
    CLEAR: lv_ctx_ok, lv_ctx_message.
    PERFORM freeze_session_contract
      USING    lv_session_id
      CHANGING lv_ctx_ok lv_ctx_message.
    IF lv_ctx_ok <> abap_true.
      lv_integrity_fail = abap_true.
      lv_integrity_msg = lv_ctx_message.
      EXIT.
    ENDIF.

    lv_before = lines( gt_staging ).
    CLEAR lv_row_idx.
    REFRESH lt_schema_keys.

    LOOP AT lt_row_objects INTO lv_row_object.
      lv_row_idx = lv_row_idx + 1.
      REFRESH: lt_row_keys, lt_row_vals, lt_cols.
      CLEAR: lv_row_ok, lv_row_msg, lv_schema_ok, lv_schema_msg,
             lv_align_ok, lv_align_msg, gv_ingest_error_msg.

      "Read the Gmail submission exactly as received. Mapping is NOT allowed
      "to decide which source headers/values exist; doing that was the cause
      "of missing Preview headers and silent blank staging values.
      PERFORM gmail_parse_row_exact
        USING    lv_row_object
        CHANGING lt_row_keys lt_row_vals lv_row_ok lv_row_msg.
      IF lv_row_ok <> abap_true.
        lv_integrity_fail = abap_true.
        lv_integrity_msg = lv_row_msg.
        EXIT.
      ENDIF.

      IF lt_schema_keys IS INITIAL.
        PERFORM gmail_resolve_schema
          USING    lt_row_keys
          CHANGING lt_schema_keys lv_schema_ok lv_schema_msg.
        IF lv_schema_ok <> abap_true.
          lv_integrity_fail = abap_true.
          lv_integrity_msg = lv_schema_msg.
          EXIT.
        ENDIF.

        CLEAR lv_preview_ok.
        PERFORM cache_gmail_preview_schema
          USING    lt_schema_keys lv_session_id
          CHANGING lv_preview_ok.
        IF lv_preview_ok <> abap_true.
          lv_integrity_fail = abap_true.
          lv_integrity_msg = gv_ingest_error_msg.
          EXIT.
        ENDIF.
      ENDIF.

      "Every row is aligned by SOURCE NAME to the one exact session schema.
      "Blank is therefore different from missing; row order cannot shift data.
      PERFORM gmail_align_row
        USING    lt_schema_keys lt_row_keys lt_row_vals
        CHANGING lt_cols lv_align_ok lv_align_msg.
      IF lv_align_ok <> abap_true.
        lv_integrity_fail = abap_true.
        lv_integrity_msg = lv_align_msg.
        EXIT.
      ENDIF.

      "Stage by exact source name against the complete Mapping snapshot.
      "Do not re-run FIELD_GUIDE/template projection and silently drop fields.
      PERFORM append_gmail_named_bup
        USING lt_schema_keys lt_cols lv_session_id lv_row_idx.
      IF gv_ingest_error_msg IS NOT INITIAL.
        lv_integrity_fail = abap_true.
        lv_integrity_msg = gv_ingest_error_msg.
        EXIT.
      ENDIF.

      CLEAR lv_preview_ok.
      PERFORM cache_gmail_preview_row
        USING    lt_cols lv_session_id lv_row_idx
        CHANGING lv_preview_ok.
      IF lv_preview_ok <> abap_true.
        lv_integrity_fail = abap_true.
        lv_integrity_msg = gv_ingest_error_msg.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_integrity_fail = abap_true.
      EXIT.
    ENDIF.

    lv_after = lines( gt_staging ).

    IF lv_after <= lv_before.
      lv_skipped = lv_skipped + 1.
      CONTINUE.
    ENDIF.

    REFRESH lt_blank_scope.
    LOOP AT gt_staging INTO DATA(ls_blank_db)
      WHERE session_id = lv_session_id.
      CLEAR ls_blank_row.
      MOVE-CORRESPONDING ls_blank_db TO ls_blank_row.
      APPEND ls_blank_row TO lt_blank_scope.
    ENDLOOP.
    CLEAR: lv_blank_ok, lv_blank_msg.
    PERFORM check_blank_contract_scope
      USING    lt_blank_scope
      CHANGING lv_blank_ok lv_blank_msg.
    IF lv_blank_ok <> abap_true.
      lv_integrity_fail = abap_true.
      lv_integrity_msg = lv_blank_msg.
      EXIT.
    ENDIF.

    CLEAR ls_audit.
    ls_audit-session_id    = lv_session_id.
    ls_audit-submission_id = ls_selected-submission_id.
    ls_audit-request_id    = ls_selected-request_id.
    ls_audit-tcode         = ls_selected-tcode.
    ls_audit-profile       = ls_selected-profile.
    ls_audit-version       = ls_selected-version.
    ls_audit-row_count     = lv_after - lv_before.
    ls_audit-file_ref      = lv_file_ref.
    ls_audit-submitted_at  = ls_selected-submitted_at.
    APPEND ls_audit TO lt_audit.

    lv_loaded_total = lv_loaded_total + ls_audit-row_count.
  ENDLOOP.

  IF lv_integrity_fail = abap_true.
    REFRESH: gt_staging, gt_staging_alv, gt_errors, gt_preview_data,
             gt_preview_src_cache, gt_preview_hdr_cache, gt_current_sessions,
             lt_audit.
    CLEAR: gv_current_batch_prefix, gv_ingest_batch_prefix,
           gv_forced_session_id, gv_current_batch_count,
           gv_current_file_name, gv_current_sheet_name, gv_current_unit_src.
    PERFORM set_row_count_fields USING 0.
    txtp_file_size = '0 B'.
    IF lv_integrity_msg IS INITIAL.
      lv_integrity_msg = 'Gmail data integrity validation failed.'.
    ENDIF.
    MESSAGE lv_integrity_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR: gv_forced_session_id,
         gv_current_file_name,
         gv_current_sheet_name,
         gv_current_unit_src.

  IF lt_audit IS INITIAL OR gt_staging IS INITIAL.
    PERFORM finish_ingest_batch.
 "no persisted staging exists, so no exact batch scope exists.
 "Do not let STATUS_0301 reload a synthetic empty batch and mask the
 "actual Gmail contract/data diagnostic.
    CLEAR: gv_current_batch_prefix,
           gv_ingest_batch_prefix,
           gv_forced_session_id,
           gv_current_batch_count.
    REFRESH: gt_current_sessions, gt_preview_src_cache, gt_preview_hdr_cache.
    PERFORM set_row_count_fields USING 0.
    txtp_file_size = '0 B'.

    IF lv_duplicate > 0 AND lv_skipped = 0.
    MESSAGE s104(zbdc) WITH lv_duplicate DISPLAY LIKE 'W'.
    ELSE.
    MESSAGE s105(zbdc) WITH lv_duplicate lv_skipped DISPLAY LIKE 'W'.
    ENDIF.
    RETURN.
  ENDIF.

  MODIFY zbdc_staging_bup FROM TABLE gt_staging.
  IF sy-subrc <> 0.
    ROLLBACK WORK.
    REFRESH: gt_staging, gt_preview_src_cache, gt_preview_hdr_cache.
    PERFORM set_row_count_fields USING 0.
    MESSAGE s136(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  LOOP AT lt_audit INTO ls_audit.
    p_transaction     = ls_audit-tcode.
    txtp_profile_name = ls_audit-profile.
    gv_profile_ver    = ls_audit-version.
    txtp_file_path    = ls_audit-file_ref.
    txtp_file_size    = 'Unknown'.

    PERFORM save_ingestion_source_log
      USING ls_audit-session_id 'GMAIL_FORM' ls_audit-file_ref.
    PERFORM update_session_summary USING ls_audit-session_id.
    PERFORM register_current_session USING ls_audit-session_id.

    CLEAR ls_meta.
    ls_meta-file_name   = ls_audit-file_ref.
    ls_meta-file_title  = ls_audit-request_id.
    ls_meta-sheet_name  = 'GMAIL_FORM'.
    ls_meta-tx_code     = ls_audit-tcode.
    ls_meta-file_size   = 'Unknown'.
    ls_meta-rows_loaded = ls_audit-row_count.
    ls_meta-channel     = 'GMAIL_FORM'.
    ls_meta-source_text = 'Gmail Form'.
    ls_meta-data_unit   = 'Submission'.
    PERFORM get_demo_now CHANGING ls_meta-upload_date ls_meta-upload_time.
    ls_meta-username    = sy-uname.
    ls_meta-owner       = sy-uname.
    ls_meta-session_id  = ls_audit-session_id.
    ls_meta-status_text = 'IMPORTED'.
    ls_meta-status_icon = icon_green_light.
    ls_meta-next_action = 'Preview then open Staging'.
    APPEND ls_meta TO gt_files_preview.
  ENDLOOP.

  PERFORM finish_ingest_batch.
  PERFORM set_row_count_fields USING lv_loaded_total.

  txtp_file_path = |GmailForm://{ lines( lt_audit ) } submission(s)|.
  txtp_file_size = 'Unknown'.

  READ TABLE gt_staging INTO ls_first_staging INDEX 1.
  IF sy-subrc = 0.
    p_transaction = ls_first_staging-tcode.
    PERFORM apply_first_staging_ctx.
  ENDIF.

  PERFORM verify_loaded_ctx
    USING    p_transaction
    CHANGING lv_ctx_ok lv_ctx_message.
  IF lv_ctx_ok <> abap_true.
    ROLLBACK WORK.
    REFRESH: gt_staging, gt_staging_alv, gt_current_sessions,
             gt_preview_src_cache, gt_preview_hdr_cache.
    CLEAR gv_current_batch_prefix.
    PERFORM set_row_count_fields USING 0.
    MESSAGE lv_ctx_message TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  COMMIT WORK AND WAIT.
  REFRESH gt_m1_gmail_selected_pending.

  lv_audit_count = lines( lt_audit ).

  MESSAGE s106(zbdc)
    WITH lv_loaded_total lv_audit_count
         lv_duplicate lv_skipped.
ENDFORM.

FORM cfg_add
  TABLES   ct_config STRUCTURE zbdc_config_bup
  USING    iv_key   TYPE csequence
           iv_value TYPE csequence.

  DATA ls_config TYPE zbdc_config_bup.

  CLEAR ls_config.
  ls_config-config_key   = iv_key.
  ls_config-config_value = iv_value.
  APPEND ls_config TO ct_config.
ENDFORM.

FORM delete_legacy_config.
 "These keys describe an upload/onboarding instance, not global runtime
 "configuration. They are removed when the user saves /oZBDC_CONFIG_BUP
 "so a future session cannot inherit stale TCODE/source/file context.
  DELETE FROM zbdc_config_bup WHERE config_key = 'SOURCE_TYPE'.
  DELETE FROM zbdc_config_bup WHERE config_key = 'TRANSACTION'.
  DELETE FROM zbdc_config_bup WHERE config_key = 'FORMAT'.
  DELETE FROM zbdc_config_bup WHERE config_key = 'FILE_PATH'.
  DELETE FROM zbdc_config_bup WHERE config_key = 'GDRIVE_URL'.

 "Never refresh plaintext credentials from a dynpro field into the config
 "table. Runtime connectors must use their protected endpoint/SM59/secure
 "store boundary, while screen values are one-session UI input only.
  DELETE FROM zbdc_config_bup WHERE config_key = 'API_KEY'.
  DELETE FROM zbdc_config_bup WHERE config_key = 'GDRIVE_API_KEY'.
ENDFORM.

FORM save_runtime_config
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lt_config TYPE STANDARD TABLE OF zbdc_config_bup,
        lv_mode   TYPE char10,
        lv_update TYPE char10,
        lv_bsize  TYPE char10,
        lv_retry  TYPE char10,
        lv_timeout TYPE char20,
        lv_bnum   TYPE i,
        lv_btxt   TYPE string,
        lv_policy_ok  TYPE abap_bool,
        lv_policy_msg TYPE string,
        lv_timeout_i  TYPE i.

  CLEAR: cv_ok, cv_message.

  PERFORM capture_runtime
    CHANGING lv_policy_ok lv_policy_msg.
  IF lv_policy_ok <> abap_true.
    cv_message = lv_policy_msg.
    RETURN.
  ENDIF.

  PERFORM parse_pos_int
    USING    txtp_batch_size 'Batch size'
    CHANGING lv_bnum lv_policy_ok lv_policy_msg lv_btxt.
  IF lv_policy_ok <> abap_true.
    cv_message = lv_policy_msg.
    RETURN.
  ENDIF.

  txtp_batch_size = lv_btxt.
  lv_bsize = lv_btxt.

  lv_timeout_i = txtp_timeout.
  IF lv_timeout_i IS INITIAL.
    lv_timeout_i = 60.
  ENDIF.
  IF lv_timeout_i < 1 OR lv_timeout_i > 300.
    cv_message = 'Runtime timeout must be between 1 and 300 seconds.'.
    RETURN.
  ENDIF.
  txtp_timeout = lv_timeout_i.
  WRITE lv_timeout_i TO lv_timeout LEFT-JUSTIFIED.
  CONDENSE lv_timeout NO-GAPS.

 "CTU preferences are persisted independently of the selected executor.
 "SM35 ignores them, but switching back to CALL TRANSACTION restores them.
  IF rb_mode_e = 'X'.
    lv_mode = 'E'.
  ELSEIF rb_mode_a = 'X'.
    lv_mode = 'A'.
  ELSE.
    lv_mode = 'N'.
  ENDIF.

  IF rb_upd_a = 'X'.
    lv_update = 'A'.
  ELSE.
    lv_update = 'S'.
  ENDIF.

  lv_retry = chkp_retry.

  REFRESH lt_config.
  PERFORM cfg_add TABLES lt_config USING 'BDC_MODE'      lv_mode.
  PERFORM cfg_add TABLES lt_config USING 'BDC_UPDATE'    lv_update.
  PERFORM cfg_add TABLES lt_config USING 'BDC_EXEC_MODE' p_bdc_mode.
  PERFORM cfg_add TABLES lt_config USING 'BATCH_SIZE'    lv_bsize.
  PERFORM cfg_add TABLES lt_config USING 'TIMEOUT'       lv_timeout.
  PERFORM cfg_add TABLES lt_config USING 'RETRY_ENABLED' lv_retry.

  PERFORM delete_legacy_config.
  MODIFY zbdc_config_bup FROM TABLE lt_config.
  IF sy-subrc = 0.
    COMMIT WORK AND WAIT.
    cv_ok = abap_true.
  ELSE.
    ROLLBACK WORK.
    cv_message = 'Error saving runtime execution configuration.'.
  ENDIF.
ENDFORM.

FORM get_drv_api_base
  CHANGING cv_url TYPE string.

  PERFORM get_config_value
    USING    'GDRIVE_API_FILES_URL'
    CHANGING cv_url.
  CONDENSE cv_url NO-GAPS.

  IF cv_url IS NOT INITIAL AND cv_url NP 'https://*'.
    CLEAR cv_url.
  ENDIF.
ENDFORM.

"& Mass Automation Batch Helpers - code only, no new SE11 fields

FORM BROWSE_FILE.
  DATA: lt_files    TYPE filetable,
        ls_file     TYPE file_table,
        lv_rc       TYPE i,
        lv_act      TYPE i,
        lv_selected TYPE i,
        lv_msg      TYPE string.

 "Browse selects N local files in one user action.
 "The complete paths are stored in GT_LOCAL_SELECTED_FILES; TXTP_FILE_PATH
 "shows only a friendly summary so long path lists cannot be truncated.
  cl_gui_frontend_services=>file_open_dialog(
    EXPORTING
      window_title   = 'Select local data file(s)'
      file_filter    = 'Data (*.xlsx;*.csv)|*.xlsx;*.csv|All (*.*)|*.*'
      multiselection = abap_true
    CHANGING
      file_table     = lt_files
      rc             = lv_rc
      user_action    = lv_act
    EXCEPTIONS
      OTHERS         = 1 ).

  IF sy-subrc <> 0
     OR lv_act <> cl_gui_frontend_services=>action_ok
     OR lv_rc <= 0.
    RETURN.
  ENDIF.

 "Clear previous browse-only state before binding the new selection.
  PERFORM clear_0300_after_browse.
 "switching/browsing a source invalidates previous source-specific picks.
  REFRESH: gt_local_selected_files, gt_m1_gmail_selected_pending.
  CLEAR gv_gdrive_file_id_temp.

  LOOP AT lt_files INTO ls_file.
    IF ls_file-filename IS INITIAL.
      CONTINUE.
    ENDIF.
    APPEND ls_file-filename TO gt_local_selected_files.
  ENDLOOP.

  lv_selected = lines( gt_local_selected_files ).
  IF lv_selected = 0.
    MESSAGE s107(zbdc) DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  IF lv_selected = 1.
    READ TABLE gt_local_selected_files INTO txtp_file_path INDEX 1.
  ELSE.
    txtp_file_path = |MULTI_LOCAL://{ lv_selected } FILES|.
  ENDIF.

  txtp_file_size = '0 B'.
  PERFORM set_row_count_fields USING 0.

  CALL METHOD cl_gui_cfw=>flush.
  lv_msg = |{ lv_selected } local file(s) selected. Press Upload/Ingest to parse all files and all business sheets.|.
  MESSAGE lv_msg TYPE 'S'.
ENDFORM.

FORM UPLOAD_AND_PARSE_EXCEL.
  IF TXTP_FILE_PATH IS INITIAL.
    MESSAGE e108(zbdc). RETURN.
  ENDIF.

  IF TXTP_FILE_PATH CP 'GoogleDrive://*'.
    PERFORM DOWNLOAD_FROM_GDRIVE_FILE.
  ELSEIF TXTP_FILE_PATH CP 'REST_API://*'.
    PERFORM UPLOAD_FROM_REST.
  ELSEIF TXTP_FILE_PATH CP 'MAILBOX://*'.
    DATA: LV_MAIL_COUNT TYPE I.
    IF GT_STAGING IS INITIAL AND GV_CURRENT_BATCH_PREFIX IS NOT INITIAL.
      PERFORM load_staging_by_batch USING GV_CURRENT_BATCH_PREFIX CHANGING LV_MAIL_COUNT.
    ELSE.
      LV_MAIL_COUNT = LINES( GT_STAGING ).
    ENDIF.
    PERFORM set_row_count_fields USING LV_MAIL_COUNT.
    MESSAGE s109(zbdc) WITH LV_MAIL_COUNT.
  ELSE.
    PERFORM UPLOAD_LOCAL_FILE.
  ENDIF.
ENDFORM.

FORM upload_local_file.

  DATA: lt_files      TYPE STANDARD TABLE OF string,
        lv_file       TYPE string,
        lt_raw        TYPE string_table,
        lv_content    TYPE string,
        lv_unit       TYPE string,
        lv_reject_unit TYPE string,
        lv_index      TYPE i,
        lv_before     TYPE i,
        lv_after      TYPE i,
        lv_loaded     TYPE i,
        lv_ok_files   TYPE i,
        lv_bad_files  TYPE i,
        lv_session_id TYPE zbdc_staging_bup-session_id,
        lv_xstr       TYPE xstring,
        lv_xok        TYPE abap_bool,
        lv_size_bytes TYPE i,
        lv_size_text  TYPE char20,
        lv_file_str   TYPE string,
        ls_file_meta  TYPE ty_files_disp,
        lv_title      TYPE char80,
        lv_sheet      TYPE char40,
        lv_raw_line   TYPE string,
        lv_size_calc  TYPE i,
        lv_line_len   TYPE i,
        lv_ctx_ok      TYPE abap_bool,
        lv_ctx_message TYPE string.

  IF txtp_file_path IS INITIAL.
    MESSAGE e110(zbdc).
    RETURN.
  ENDIF.

  CLEAR gv_ingest_error_msg.

 "use the real multi-selection table first. Legacy single-file and
 "older semicolon paths remain backward compatible.
  IF gt_local_selected_files IS NOT INITIAL.
    lt_files = gt_local_selected_files.
  ELSE.
    SPLIT txtp_file_path AT ';' INTO TABLE lt_files.
    DELETE lt_files WHERE table_line IS INITIAL.
  ENDIF.

  IF lt_files IS INITIAL.
    gv_ingest_error_msg = 'No local file selected.'.
    MESSAGE gv_ingest_error_msg TYPE 'E'.
    RETURN.
  ENDIF.

  REFRESH gt_staging.

  PERFORM start_ingest_batch.

  CLEAR: lv_index,
         lv_loaded,
         lv_ok_files,
         lv_bad_files.

  LOOP AT lt_files INTO lv_file.

    CLEAR: lv_size_bytes,
           lv_size_text,
           lv_content,
           lv_xstr,
           lv_xok.

    CLEAR gv_ingest_error_msg.

    lv_file_str = lv_file.

    cl_gui_frontend_services=>file_get_size(
      EXPORTING
        file_name = lv_file_str
      IMPORTING
        file_size = lv_size_bytes
      EXCEPTIONS
        OTHERS    = 1 ).

    IF sy-subrc = 0.
      PERFORM format_file_size
        USING    lv_size_bytes
        CHANGING lv_size_text.
    ELSE.
      lv_size_text = 'Unknown'.
    ENDIF.

    txtp_file_size = lv_size_text.

 " XLSX path

    IF lv_file CP '*.xlsx' OR lv_file CP '*.XLSX'.

      PERFORM read_local_xstr
        USING    lv_file
        CHANGING lv_xstr lv_xok.

      IF lv_xok = abap_true.
        PERFORM ingest_xlsx_xstr
          USING    lv_file 'LOCAL' lv_xstr
          CHANGING lv_index lv_loaded lv_ok_files lv_bad_files.
      ELSE.
        lv_bad_files = lv_bad_files + 1.
        gv_ingest_error_msg = |Cannot read XLSX file: { lv_file }|.
        lv_index = lv_index + 1.
        PERFORM make_batch_session USING lv_index CHANGING lv_session_id.
        CLEAR lv_reject_unit.
        PERFORM p1_compose_unit_name
          USING    lv_file 'DATA'
          CHANGING lv_reject_unit.
        PERFORM p1_save_rejected_unit
          USING lv_session_id 'LOCAL' lv_reject_unit gv_ingest_error_msg.
      ENDIF.

      CONTINUE.

    ENDIF.

 " CSV path. User-file JSON/XML are outside the approved inbound
 " contract; Gmail's internal JSON transport is handled separately.

    IF lv_file NP '*.csv' AND lv_file NP '*.CSV'.
      lv_bad_files = lv_bad_files + 1.
      gv_ingest_error_msg = |Unsupported local file type: { lv_file }. Use CSV or XLSX.|.
      lv_index = lv_index + 1.
      PERFORM make_batch_session USING lv_index CHANGING lv_session_id.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name
        USING    lv_file 'DATA'
        CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'LOCAL' lv_reject_unit gv_ingest_error_msg.
      CONTINUE.
    ENDIF.

    lv_index = lv_index + 1.

    PERFORM make_batch_session
      USING    lv_index
      CHANGING lv_session_id.

    gv_forced_session_id  = lv_session_id.
    gv_current_file_name  = lv_file.
    gv_current_sheet_name = 'DATA'.
    gv_current_unit_src   = 'LOCAL'.

    REFRESH lt_raw.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename = lv_file
        filetype = 'ASC'
        codepage = '4110'
      CHANGING
        data_tab = lt_raw
      EXCEPTIONS
        OTHERS   = 1 ).

    IF sy-subrc <> 0.
      lv_bad_files = lv_bad_files + 1.
      gv_ingest_error_msg = |GUI_UPLOAD failed for local file: { lv_file }|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name
        USING    lv_file 'DATA'
        CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'LOCAL' lv_reject_unit gv_ingest_error_msg.

      CLEAR: gv_forced_session_id,
             gv_current_file_name,
             gv_current_sheet_name,
             gv_current_unit_src.

      CONTINUE.
    ENDIF.

    IF lt_raw IS INITIAL.
      lv_bad_files = lv_bad_files + 1.
      gv_ingest_error_msg = |GUI_UPLOAD read 0 lines from local file: { lv_file }|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name
        USING    lv_file 'DATA'
        CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'LOCAL' lv_reject_unit gv_ingest_error_msg.

      CLEAR: gv_forced_session_id,
             gv_current_file_name,
             gv_current_sheet_name,
             gv_current_unit_src.

      CONTINUE.
    ENDIF.

 "Frontend FILE_GET_SIZE is not reliable in every SAP GUI release.
 "If Browse/Upload shows 0 B while rows are loaded, calculate a safe
 "display size from the raw file content after GUI_UPLOAD.
    IF lv_size_bytes IS INITIAL
       OR lv_size_text = '0 B'
       OR lv_size_text IS INITIAL.

      CLEAR lv_size_calc.

      LOOP AT lt_raw INTO lv_raw_line.
        lv_line_len  = strlen( lv_raw_line ).
        lv_size_calc = lv_size_calc + lv_line_len + 2.
      ENDLOOP.

      IF lv_size_calc > 0.
        lv_size_bytes = lv_size_calc.

        PERFORM format_file_size
          USING    lv_size_bytes
          CHANGING lv_size_text.

        txtp_file_size = lv_size_text.
      ENDIF.

    ENDIF.

    CONCATENATE LINES OF lt_raw INTO lv_content.
    CONDENSE lv_content.

    lv_before = lines( gt_staging ).

    PERFORM process_csv_rows USING lt_raw.

    lv_after = lines( gt_staging ).

    CLEAR: gv_forced_session_id,
           gv_current_file_name,
           gv_current_sheet_name,
           gv_current_unit_src.

    IF lv_after > lv_before.

      lv_ok_files = lv_ok_files + 1.
      lv_loaded   = lv_loaded + ( lv_after - lv_before ).

      MODIFY zbdc_staging_bup FROM TABLE gt_staging.

      PERFORM p1_compose_unit_name
        USING    lv_file 'DATA'
        CHANGING lv_unit.

      PERFORM save_ingestion_source_log
        USING lv_session_id 'LOCAL' lv_unit.

      PERFORM update_session_summary
        USING lv_session_id.

      PERFORM register_current_session
        USING lv_session_id.

      CLEAR ls_file_meta.

      PERFORM p1_split_unit_name
        USING    lv_unit
        CHANGING lv_title lv_sheet.

      ls_file_meta-file_name   = lv_unit.
      ls_file_meta-file_title  = lv_title.
      ls_file_meta-sheet_name  = lv_sheet.
      ls_file_meta-file_size   = lv_size_text.
      ls_file_meta-rows_loaded = lv_after - lv_before.
      ls_file_meta-channel     = 'LOCAL_INGESTION'.
      PERFORM get_demo_now CHANGING ls_file_meta-upload_date ls_file_meta-upload_time.
      ls_file_meta-username    = sy-uname.
      ls_file_meta-session_id  = lv_session_id.
      ls_file_meta-tx_code     = p_transaction.

      APPEND ls_file_meta TO gt_files_preview.

    ELSE.

      lv_bad_files = lv_bad_files + 1.

      IF gv_ingest_error_msg IS INITIAL.
        gv_ingest_error_msg =
          |Parser did not create staging rows for file { lv_file }. Check CSV header, mapping profile, and data rows.|.
      ENDIF.

      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name
        USING    lv_file 'DATA'
        CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'LOCAL' lv_reject_unit gv_ingest_error_msg.

    ENDIF.

  ENDLOOP.

  CLEAR gv_forced_session_id.

  PERFORM finish_ingest_batch.

  IF lv_loaded > 0.

    PERFORM verify_loaded_ctx
      USING    space
      CHANGING lv_ctx_ok lv_ctx_message.
    IF lv_ctx_ok <> abap_true.
      ROLLBACK WORK.
      REFRESH: gt_staging, gt_staging_alv, gt_current_sessions.
      CLEAR: gv_current_batch_prefix, lv_loaded.
      PERFORM set_row_count_fields USING 0.
      MESSAGE lv_ctx_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    PERFORM set_row_count_fields USING lv_loaded.

    CLEAR gv_ingest_error_msg.

    MESSAGE s111(zbdc)
      WITH gv_current_batch_prefix lv_loaded
           lv_ok_files lv_bad_files.

  ELSE.

    CLEAR: txtp_row_count,
           txtp_row,
           txtp_rows,
           txtp_loaded,
           txtp_loaded_rows,
           txtp_rows_loaded.

    "Rejected uploads are still durable ingestion history. No staging rows
    "exist in this branch, so committing the rejection audit cannot publish
    "unverified business data.
    IF lv_bad_files > 0.
      COMMIT WORK AND WAIT.
    ENDIF.

    IF gv_ingest_error_msg IS NOT INITIAL.
      MESSAGE gv_ingest_error_msg TYPE 'S' DISPLAY LIKE 'W'.
    ELSE.
      MESSAGE s112(zbdc) DISPLAY LIKE 'W'.
    ENDIF.

  ENDIF.

ENDFORM.

"& Form SELECT_GDRIVE_FILE_PATH
"& Flow: open configured Apps Script portal and select a Drive file
"& → user Make a Copy Sheet → dien data → confirm
"& → OAuth token-relay → liet ke → chon file

FORM select_gdrive_file_path.
  DATA: lo_client       TYPE REF TO if_http_client,
        lv_resp         TYPE string,
        lv_url          TYPE string,
        lv_code         TYPE i,
        lv_qcode        TYPE string,
        lv_ret          TYPE c,
        lt_sval         TYPE STANDARD TABLE OF sval,
        ls_sval         TYPE sval,
        lv_gas_base_url TYPE string,
        lv_token_url    TYPE string,
        lv_auth_url     TYPE string,
        lv_ready        TYPE c LENGTH 1,
        lv_cfg_file_id  TYPE string,
        lv_cfg_file_nm  TYPE string,
        lv_tcode_url    TYPE string,
        lv_api_files_url TYPE string.

  TYPES: BEGIN OF ty_gfile,
           id       TYPE string,
           name     TYPE string,
           mimetype TYPE string,
         END OF ty_gfile.
  TYPES: BEGIN OF ty_resp,
           files TYPE STANDARD TABLE OF ty_gfile WITH DEFAULT KEY,
         END OF ty_resp.
  DATA: ls_resp  TYPE ty_resp,
        ls_gfile TYPE ty_gfile.

  TYPES: BEGIN OF ty_f4_data,
           mark      TYPE c LENGTH 1,
           sel_no    TYPE char4,
           file_name TYPE c LENGTH 120,
           file_type TYPE char20,
           file_id   TYPE char100,
         END OF ty_f4_data.
  DATA: lt_f4_table TYPE STANDARD TABLE OF ty_f4_data,
        ls_f4_row   TYPE ty_f4_data.

  DATA: lt_gd_fieldcat TYPE slis_t_fieldcat_alv,
        ls_gd_fieldcat TYPE slis_fieldcat_alv,
        ls_gd_selfield TYPE slis_selfield,
        lv_gd_exit     TYPE c,
        lv_seq         TYPE i,
        lv_seq_txt     TYPE c LENGTH 4,
        lv_display_nm  TYPE c LENGTH 120,
        lv_file_kind   TYPE c LENGTH 20,
        lv_selected    TYPE i,
        lv_ids         TYPE string,
        lv_names       TYPE string,
        lv_refresh     TYPE c LENGTH 1,
        lv_auth_ok     TYPE abap_bool.

  PERFORM load_source_config.

 "Optional configured-file path. It remains profile-independent: the file
 "header is classified during ingestion against ACTIVE profile signatures.
  SELECT SINGLE config_value
    FROM zbdc_config_bup
    WHERE config_key = 'GDRIVE_FILE_ID'
    INTO @lv_cfg_file_id.
  SELECT SINGLE config_value
    FROM zbdc_config_bup
    WHERE config_key = 'GDRIVE_FILE_NAME'
    INTO @lv_cfg_file_nm.
  CONDENSE lv_cfg_file_id NO-GAPS.
  CONDENSE lv_cfg_file_nm.

  IF lv_cfg_file_id IS NOT INITIAL.
    IF lv_cfg_file_nm IS INITIAL.
      lv_cfg_file_nm = lv_cfg_file_id.
    ENDIF.
    IF gv_gdrive_token IS INITIAL AND txtp_api_key IS INITIAL.
      PERFORM ensure_gdrive_token CHANGING lv_auth_ok.
      IF lv_auth_ok <> abap_true.
        RETURN.
      ENDIF.
    ENDIF.

    PERFORM clear_0300_after_browse.
    REFRESH: gt_local_selected_files, gt_m1_gmail_selected_pending.
    gv_gdrive_file_id_temp = lv_cfg_file_id.
    txtp_file_path = 'GoogleDrive://' && lv_cfg_file_nm.
    txtp_file_size = '0 B'.
    PERFORM set_row_count_fields USING 0.
    MESSAGE s702(zbdc).
    RETURN.
  ENDIF.

  lv_gas_base_url = txtp_gdrive_url.
  CONDENSE lv_gas_base_url NO-GAPS.
  IF lv_gas_base_url IS INITIAL.
    MESSAGE e703(zbdc).
    RETURN.
  ENDIF.
  IF lv_gas_base_url CS '?'.
    SPLIT lv_gas_base_url AT '?' INTO lv_gas_base_url lv_resp.
  ENDIF.

 "Google Drive authorization is shared for both Browse and Generate
 "Template. If the token already exists in this SAP session, do not ask
 "for a second 6-digit code; just list Drive files immediately.
  PERFORM ensure_gdrive_token CHANGING lv_auth_ok.
  IF lv_auth_ok <> abap_true.
    RETURN.
  ENDIF.

  PERFORM get_drv_api_base CHANGING lv_api_files_url.
  IF lv_api_files_url IS INITIAL.
    MESSAGE e704(zbdc).
    RETURN.
  ENDIF.

  DO.
    CLEAR: ls_resp, ls_gfile, lt_f4_table, ls_f4_row,
           lv_selected, lv_ids, lv_names, lv_refresh.

 "CSV uploaded from browsers/desktop clients does not always
 "keep MIME text/csv. Include common CSV MIME values and supported
 "extensions, while the ABAP filter below still rejects TXT/XLS/others.
    lv_url = lv_api_files_url && '?q=' &&
      cl_http_utility=>escape_url(
        |'me' in owners and trashed=false and (| &&
        |mimeType='application/vnd.google-apps.spreadsheet' or | &&
        |mimeType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' or | &&
        |mimeType='text/csv' or mimeType='application/csv' or | &&
        |mimeType='application/vnd.ms-excel' or | &&
        |name contains '.csv' or name contains '.CSV' or | &&
        |name contains '.xlsx' or name contains '.XLSX')| ) &&
      '&fields=files(id,name,mimeType)&pageSize=100&orderBy=modifiedTime%20desc'.

    cl_http_client=>create_by_url(
      EXPORTING url = lv_url
      IMPORTING client = lo_client
      EXCEPTIONS OTHERS = 1 ).
    IF sy-subrc <> 0.
    MESSAGE e117(zbdc).
      RETURN.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    lo_client->request->set_header_field(
      name  = 'Authorization'
      value = |Bearer { gv_gdrive_token }| ).
    lo_client->send( EXCEPTIONS OTHERS = 1 ).
    lo_client->receive( EXCEPTIONS OTHERS = 1 ).
    lo_client->response->get_status( IMPORTING code = lv_code ).
    lv_resp = lo_client->response->get_cdata( ).
    lo_client->close( ).

    IF lv_code = 401 OR lv_code = 403.
      CLEAR gv_gdrive_token.
    MESSAGE s705(zbdc) DISPLAY LIKE 'W'.
      PERFORM ensure_gdrive_token CHANGING lv_auth_ok.
      IF lv_auth_ok = abap_true.
        CONTINUE.
      ENDIF.
      RETURN.
    ENDIF.

    IF lv_code <> 200.
    MESSAGE e118(zbdc) WITH lv_code.
      RETURN.
    ENDIF.

    /ui2/cl_json=>deserialize(
      EXPORTING
        json        = lv_resp
        pretty_name = /ui2/cl_json=>pretty_mode-none
      CHANGING
        data        = ls_resp ).

    IF ls_resp-files IS INITIAL.
    MESSAGE w119(zbdc).
      RETURN.
    ENDIF.

    CLEAR ls_f4_row.
    ls_f4_row-sel_no    = '0'.
    ls_f4_row-file_name = '[Refresh] Reload Google Drive file list'.
    ls_f4_row-file_type = 'Action'.
    ls_f4_row-file_id   = '__REFRESH__'.
    APPEND ls_f4_row TO lt_f4_table.

    CLEAR lv_seq.
    LOOP AT ls_resp-files INTO ls_gfile.
      lv_seq = lv_seq + 1.
      CLEAR: ls_f4_row, lv_seq_txt, lv_display_nm, lv_file_kind.
      WRITE lv_seq TO lv_seq_txt LEFT-JUSTIFIED.
      CONDENSE lv_seq_txt NO-GAPS.

      lv_display_nm = ls_gfile-name.
      CONDENSE lv_display_nm.
      IF lv_display_nm IS INITIAL OR lv_display_nm = ls_gfile-id.
        lv_display_nm = |Drive file { lv_seq_txt }|.
      ENDIF.

      CASE ls_gfile-mimetype.
        WHEN 'application/vnd.google-apps.spreadsheet'.
          lv_file_kind = 'Google Sheet'.
        WHEN 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.
          lv_file_kind = 'XLSX'.
        WHEN 'text/csv' OR 'application/csv'.
          lv_file_kind = 'CSV'.
        WHEN 'application/vnd.ms-excel'.
 "This MIME is also used by legacy XLS. Accept only a real .CSV name.
          IF ls_gfile-name CP '*.csv' OR ls_gfile-name CP '*.CSV'.
            lv_file_kind = 'CSV'.
          ELSE.
            CONTINUE.
          ENDIF.
        WHEN OTHERS.
 "Generic MIME is accepted only when the real extension is supported.
          IF ls_gfile-name CP '*.csv' OR ls_gfile-name CP '*.CSV'.
            lv_file_kind = 'CSV'.
          ELSEIF ls_gfile-name CP '*.xlsx' OR ls_gfile-name CP '*.XLSX'.
            lv_file_kind = 'XLSX'.
          ELSE.
            CONTINUE.
          ENDIF.
      ENDCASE.

      ls_f4_row-sel_no    = lv_seq_txt.
      ls_f4_row-file_name = lv_display_nm.
      ls_f4_row-file_type = lv_file_kind.
      ls_f4_row-file_id   = ls_gfile-id.
      APPEND ls_f4_row TO lt_f4_table.
    ENDLOOP.

    REFRESH lt_gd_fieldcat.
    DEFINE add_gd_fcat.
      CLEAR ls_gd_fieldcat.
      ls_gd_fieldcat-fieldname = &1.
      ls_gd_fieldcat-seltext_s = &2.
      ls_gd_fieldcat-seltext_m = &3.
      ls_gd_fieldcat-seltext_l = &3.
      ls_gd_fieldcat-outputlen = &4.
      ls_gd_fieldcat-no_out    = &5.
      APPEND ls_gd_fieldcat TO lt_gd_fieldcat.
    END-OF-DEFINITION.

    add_gd_fcat 'SEL_NO'    'No'   'No'           4  ''.
    add_gd_fcat 'FILE_NAME' 'File' 'File Name'    62 ''.
    add_gd_fcat 'FILE_TYPE' 'Type' 'File Type'    16 ''.
    add_gd_fcat 'FILE_ID'   'ID'   'Technical ID' 10 'X'.

    CLEAR: ls_gd_selfield, lv_gd_exit.
    CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
      EXPORTING
        i_title               = 'Google Drive Files'
        i_selection           = 'X'
        i_zebra               = 'X'
        i_checkbox_fieldname  = 'MARK'
        i_tabname             = 'LT_F4_TABLE'
        it_fieldcat           = lt_gd_fieldcat
        i_screen_start_column = 8
        i_screen_start_line   = 2
        i_screen_end_column   = 112
        i_screen_end_line     = 22
      IMPORTING
        es_selfield           = ls_gd_selfield
        e_exit                = lv_gd_exit
      TABLES
        t_outtab              = lt_f4_table
      EXCEPTIONS
        program_error         = 1
        OTHERS                = 2.

    IF lv_gd_exit = 'X' OR sy-subrc <> 0.
    MESSAGE s120(zbdc).
      RETURN.
    ENDIF.

    LOOP AT lt_f4_table INTO ls_f4_row WHERE mark = 'X'.
      IF ls_f4_row-file_id = '__REFRESH__'.
        lv_refresh = 'X'.
      ELSEIF ls_f4_row-file_id IS NOT INITIAL.
        lv_selected = lv_selected + 1.
        lv_ids      = ls_f4_row-file_id && '|' && ls_f4_row-file_type.
        lv_names    = ls_f4_row-file_name.
      ENDIF.
    ENDLOOP.

    IF lv_selected = 0 AND lv_refresh IS INITIAL AND
       ls_gd_selfield-tabindex IS NOT INITIAL.
      READ TABLE lt_f4_table INTO ls_f4_row INDEX ls_gd_selfield-tabindex.
      IF sy-subrc = 0.
        IF ls_f4_row-file_id = '__REFRESH__'.
          lv_refresh = 'X'.
        ELSEIF ls_f4_row-file_id IS NOT INITIAL.
          lv_selected = 1.
          lv_ids      = ls_f4_row-file_id && '|' && ls_f4_row-file_type.
          lv_names    = ls_f4_row-file_name.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lv_refresh = 'X'.
    MESSAGE s121(zbdc).
      CONTINUE.
    ENDIF.
    IF lv_selected <> 1.
    MESSAGE s122(zbdc) DISPLAY LIKE 'W'.
      CONTINUE.
    ENDIF.

    PERFORM clear_0300_after_browse.
    REFRESH: gt_local_selected_files, gt_m1_gmail_selected_pending.
    gv_gdrive_file_id_temp = lv_ids.
    txtp_file_path = 'GoogleDrive://' && lv_names.
    txtp_file_size = '0 B'.
    PERFORM set_row_count_fields USING 0.
    REFRESH: gt_staging, gt_staging_alv, gt_preview_data.
    PERFORM reset_0300_all_alv.

    MESSAGE s123(zbdc).
    EXIT.
  ENDDO.
ENDFORM.

"& Form download_gdrive_script_csv
"& Apps Script CSV endpoint path for Google Drive onboarding.
"& Keeps legacy local/SM35 flows untouched.

FORM download_from_gdrive_file.
  DATA: lo_client        TYPE REF TO if_http_client,
        lo_conv          TYPE REF TO cl_abap_conv_in_ce,
        lv_code          TYPE i,
        lv_url           TYPE string,
        lv_resp          TYPE string,
        lt_marked_files  TYPE TABLE OF string,
        lt_file_names    TYPE TABLE OF string,
        lv_current_token TYPE string,
        lv_current_id    TYPE string,
        lv_file_kind     TYPE string,
        lv_download_mode TYPE c LENGTH 1,
        lv_file_name     TYPE string,
        lv_path_names    TYPE string,
        lt_raw           TYPE string_table,
        lv_size          TYPE i,
        lv_index         TYPE i,
        lv_file_index    TYPE i,
        lv_before        TYPE i,
        lv_after         TYPE i,
        lv_loaded        TYPE i,
        lv_ok_files      TYPE i,
        lv_bad_files     TYPE i,
        lv_session_id    TYPE zbdc_staging_bup-session_id,
        ls_gdrive_meta   TYPE ty_files_disp,
        lv_payload_xstr  TYPE xstring,
        lv_auth_ok       TYPE abap_bool,
        lv_last_error    TYPE string,
        lv_reject_unit  TYPE string,
        lv_ctx_ok       TYPE abap_bool,
        lv_ctx_message  TYPE string,
        lv_api_files_url TYPE string.

  CONSTANTS lc_utf8_bom TYPE x LENGTH 3 VALUE 'EFBBBF'.

  PERFORM load_source_config.

  IF gv_gdrive_file_id_temp = 'APPSCRIPT_CSV'.
    PERFORM download_gdrive_script_csv.
    RETURN.
  ENDIF.

  IF gv_gdrive_file_id_temp IS INITIAL.
    MESSAGE e124(zbdc).
    RETURN.
  ENDIF.

  IF gv_gdrive_token IS INITIAL AND txtp_api_key IS INITIAL.
    PERFORM ensure_gdrive_token CHANGING lv_auth_ok.
    IF lv_auth_ok <> abap_true.
    MESSAGE e706(zbdc).
      RETURN.
    ENDIF.
  ENDIF.

  PERFORM get_drv_api_base CHANGING lv_api_files_url.
  IF lv_api_files_url IS INITIAL.
    MESSAGE e704(zbdc).
    RETURN.
  ENDIF.

  SPLIT gv_gdrive_file_id_temp AT ';' INTO TABLE lt_marked_files.
  lv_path_names = txtp_file_path.
  REPLACE FIRST OCCURRENCE OF 'GoogleDrive://' IN lv_path_names WITH ''.
  SPLIT lv_path_names AT ';' INTO TABLE lt_file_names.

  REFRESH gt_staging.
  PERFORM start_ingest_batch.
  CLEAR: lv_index, lv_file_index, lv_loaded, lv_ok_files,
         lv_bad_files, lv_last_error.

  LOOP AT lt_marked_files INTO lv_current_token.
    CLEAR: lv_current_id, lv_file_kind, lv_download_mode,
           lv_payload_xstr, lv_resp, lt_raw, gv_ingest_error_msg.

    IF lv_current_token IS INITIAL.
      CONTINUE.
    ENDIF.

 "picker persists FILE_ID|FILE_KIND. Configured legacy IDs remain
 "supported and are inferred from the real file extension below.
    IF lv_current_token CS '|'.
      SPLIT lv_current_token AT '|'
        INTO lv_current_id lv_file_kind.
    ELSE.
      lv_current_id = lv_current_token.
    ENDIF.
    CONDENSE lv_current_id NO-GAPS.
    CONDENSE lv_file_kind.
    TRANSLATE lv_file_kind TO UPPER CASE.
    IF lv_file_kind = 'GOOGLE SHEET'.
      lv_file_kind = 'SHEET'.
    ENDIF.

    lv_file_index = lv_file_index + 1.
    READ TABLE lt_file_names INTO lv_file_name INDEX lv_file_index.
    IF lv_file_name IS INITIAL.
      lv_file_name = lv_current_id.
    ENDIF.

    IF lv_file_kind IS INITIAL.
      IF lv_file_name CP '*.csv' OR lv_file_name CP '*.CSV'.
        lv_file_kind = 'CSV'.
      ELSEIF lv_file_name CP '*.xlsx' OR lv_file_name CP '*.XLSX'.
        lv_file_kind = 'XLSX'.
      ELSE.
        lv_file_kind = 'SHEET'.
      ENDIF.
    ENDIF.

    lv_index = lv_index + 1.
    PERFORM make_batch_session USING lv_index CHANGING lv_session_id.
    gv_forced_session_id  = lv_session_id.
    gv_current_file_name  = lv_file_name.
    gv_current_sheet_name = 'DATA'.
    gv_current_unit_src   = 'GDRIVE'.

 "The selected picker type is authoritative. Google Workspace files use
 "/export; uploaded CSV/XLSX binaries use alt=media. Unknown types fail.
    IF lv_file_kind = 'CSV' OR lv_file_kind = 'XLSX'.
      lv_download_mode = 'M'.
      lv_url = lv_api_files_url && '/' &&
               lv_current_id && '?alt=media'.
    ELSEIF lv_file_kind = 'SHEET'.
      lv_download_mode = 'E'.
      lv_url = lv_api_files_url && '/' &&
               lv_current_id && '/export?mimeType=text%2Fcsv'.
    ELSE.
      lv_bad_files = lv_bad_files + 1.
      lv_last_error = |Unsupported Drive file type { lv_file_kind } for { lv_file_name }.|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    IF gv_gdrive_token IS INITIAL AND txtp_api_key IS NOT INITIAL.
      lv_url = lv_url && '&key=' && txtp_api_key.
    ENDIF.

    CLEAR lo_client.
    cl_http_client=>create_by_url(
      EXPORTING url = lv_url
      IMPORTING client = lo_client
      EXCEPTIONS OTHERS = 1 ).

    IF sy-subrc <> 0 OR lo_client IS INITIAL.
      lv_bad_files = lv_bad_files + 1.
      lv_last_error = |Cannot create Drive HTTP client for { lv_file_name }.|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    lo_client->request->set_method( 'GET' ).
    lo_client->request->set_header_field(
      name  = 'Accept-Encoding'
      value = 'identity' ).
    IF gv_gdrive_token IS NOT INITIAL.
      lo_client->request->set_header_field(
        name  = 'Authorization'
        value = |Bearer { gv_gdrive_token }| ).
    ENDIF.
    lo_client->send( EXCEPTIONS OTHERS = 1 ).
    lo_client->receive( EXCEPTIONS OTHERS = 1 ).
    lo_client->response->get_status( IMPORTING code = lv_code ).

    IF lv_code <> 200.
      lv_bad_files = lv_bad_files + 1.
      IF lv_code = 401 OR lv_code = 403.
        lv_last_error = |Drive file { lv_file_name } rejected HTTP { lv_code }; authorize the owning user again.|.
      ELSE.
        lv_last_error = |Drive file { lv_file_name } download failed HTTP { lv_code }.|.
      ENDIF.
      lo_client->close( ).
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    lv_payload_xstr = lo_client->response->get_data( ).
    lo_client->close( ).

    IF lv_payload_xstr IS INITIAL.
      lv_bad_files = lv_bad_files + 1.
      lv_last_error = |Drive returned an empty body for { lv_file_name }.|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    IF lv_file_kind = 'XLSX'.
      lv_before = lines( gt_staging ).
      CLEAR gv_ingest_error_msg.
      PERFORM ingest_xlsx_xstr
        USING    lv_file_name 'GDRIVE' lv_payload_xstr
        CHANGING lv_index lv_loaded lv_ok_files lv_bad_files.
      lv_after = lines( gt_staging ).
      IF lv_after <= lv_before.
        IF gv_ingest_error_msg IS NOT INITIAL.
          lv_last_error = gv_ingest_error_msg.
        ELSE.
          lv_last_error =
            |Drive XLSX { lv_file_name } downloaded but produced no staging rows.|.
        ENDIF.
      ENDIF.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

 "CSV/Google-Sheet export is binary HTTP content. Remove UTF-8 BOM and
 "convert explicitly; GET_CDATA is not reliable for uploaded CSV bytes.
    IF xstrlen( lv_payload_xstr ) >= 3
       AND lv_payload_xstr(3) = lc_utf8_bom.
      lv_payload_xstr = lv_payload_xstr+3.
    ENDIF.

    CLEAR lv_resp.
    TRY.
        lo_conv = cl_abap_conv_in_ce=>create(
                    encoding    = 'UTF-8'
                    replacement = '#'
                    input       = lv_payload_xstr ).
        lo_conv->read( IMPORTING data = lv_resp ).
      CATCH cx_root.
        TRY.
            lo_conv = cl_abap_conv_in_ce=>create(
                        encoding    = '1100'
                        replacement = '#'
                        input       = lv_payload_xstr ).
            lo_conv->read( IMPORTING data = lv_resp ).
          CATCH cx_root.
            CLEAR lv_resp.
        ENDTRY.
    ENDTRY.

    IF lv_resp IS INITIAL.
      lv_bad_files = lv_bad_files + 1.
      lv_last_error = |Drive CSV { lv_file_name } could not be converted to text.|.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
      CLEAR: gv_forced_session_id, gv_current_file_name,
             gv_current_sheet_name, gv_current_unit_src.
      CONTINUE.
    ENDIF.

    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf
      IN lv_resp WITH cl_abap_char_utilities=>newline.
    REFRESH lt_raw.
    SPLIT lv_resp AT cl_abap_char_utilities=>newline INTO TABLE lt_raw.
    DELETE lt_raw WHERE table_line IS INITIAL.

    lv_size = xstrlen( lv_payload_xstr ).
    IF lv_size IS INITIAL.
      lv_size = strlen( lv_resp ).
    ENDIF.
    PERFORM format_file_size USING lv_size CHANGING txtp_file_size.

    CLEAR gv_ingest_error_msg.
    lv_before = lines( gt_staging ).
    PERFORM process_csv_rows USING lt_raw.
    lv_after = lines( gt_staging ).
    CLEAR: gv_forced_session_id, gv_current_file_name,
           gv_current_sheet_name, gv_current_unit_src.

    IF lv_after > lv_before.
      lv_ok_files = lv_ok_files + 1.
      lv_loaded   = lv_loaded + ( lv_after - lv_before ).
      MODIFY zbdc_staging_bup FROM TABLE gt_staging.

      DATA lv_gd_unit TYPE string.
      PERFORM p1_compose_unit_name
        USING    lv_file_name 'DATA'
        CHANGING lv_gd_unit.
      PERFORM save_ingestion_source_log
        USING lv_session_id 'GDRIVE' lv_gd_unit.
      PERFORM update_session_summary USING lv_session_id.
      PERFORM register_current_session USING lv_session_id.

      CLEAR ls_gdrive_meta.
      ls_gdrive_meta-file_name = lv_gd_unit.
      PERFORM p1_split_unit_name
        USING    lv_gd_unit
        CHANGING ls_gdrive_meta-file_title ls_gdrive_meta-sheet_name.
      ls_gdrive_meta-file_size   = txtp_file_size.
      ls_gdrive_meta-rows_loaded = lv_after - lv_before.
      ls_gdrive_meta-channel     = 'GDRIVE_INGESTION'.
      PERFORM get_demo_now CHANGING ls_gdrive_meta-upload_date ls_gdrive_meta-upload_time.
      ls_gdrive_meta-username    = sy-uname.
      ls_gdrive_meta-owner       = sy-uname.
      ls_gdrive_meta-session_id  = lv_session_id.
      ls_gdrive_meta-tx_code     = p_transaction.
      APPEND ls_gdrive_meta TO gt_files_preview.
    ELSE.
      lv_bad_files = lv_bad_files + 1.
      IF gv_ingest_error_msg IS NOT INITIAL.
        lv_last_error = |{ lv_file_name }: { gv_ingest_error_msg }|.
      ELSE.
        lv_last_error = |{ lv_file_name }: parser created no staging rows.|.
      ENDIF.
      CLEAR lv_reject_unit.
      PERFORM p1_compose_unit_name USING lv_file_name 'DATA' CHANGING lv_reject_unit.
      PERFORM p1_save_rejected_unit
        USING lv_session_id 'GDRIVE' lv_reject_unit lv_last_error.
    ENDIF.
  ENDLOOP.

  CLEAR: gv_forced_session_id, gv_current_file_name,
         gv_current_sheet_name, gv_current_unit_src.
  PERFORM finish_ingest_batch.

  IF lv_loaded > 0.
    PERFORM verify_loaded_ctx
      USING    space
      CHANGING lv_ctx_ok lv_ctx_message.
    IF lv_ctx_ok <> abap_true.
      ROLLBACK WORK.
      REFRESH: gt_staging, gt_staging_alv, gt_current_sessions.
      CLEAR: gv_current_batch_prefix, lv_loaded.
      PERFORM set_row_count_fields USING 0.
      MESSAGE lv_ctx_message TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.
    PERFORM set_row_count_fields USING lv_loaded.
    MESSAGE s125(zbdc)
      WITH gv_current_batch_prefix lv_loaded
           lv_ok_files lv_bad_files.
  ELSE.
 "the download may have succeeded while parsing/contract binding
 "created zero staging rows. Rejected attempts remain durable Preview Files
 "history even though there is no executable staging scope.
    IF lv_bad_files > 0.
      COMMIT WORK AND WAIT.
    ENDIF.
    CLEAR: gv_current_batch_prefix,
           gv_ingest_batch_prefix,
           gv_forced_session_id,
           gv_current_batch_count.
    PERFORM set_row_count_fields USING 0.
    IF lv_last_error IS INITIAL.
      lv_last_error = 'No valid Google Drive data rows were loaded.'.
    ENDIF.
    MESSAGE lv_last_error TYPE 'S' DISPLAY LIKE 'E'.
  ENDIF.
ENDFORM.

FORM UPLOAD_FROM_REST.
  DATA: LO_CLIENT  TYPE REF TO IF_HTTP_CLIENT,
        LV_CODE    TYPE I,
        LV_REASON  TYPE STRING,
        LT_RAW     TYPE STRING_TABLE,
        LV_RESP    TYPE STRING,
        LV_SIZE    TYPE I,
        LV_SIZE_KB TYPE P DECIMALS 1,
        LV_REST_SESSION TYPE ZBDC_STAGING_BUP-SESSION_ID,
        LV_REST_XSTR TYPE XSTRING,
        LV_REST_HIST_PATH TYPE STRING,
        LV_REST_REJECT_REASON TYPE STRING.

 "REST pull is an explicit source adapter. Gmail mailbox/form ingestion uses
 "its own command and is never selected implicitly from this routine.
  PERFORM LOAD_SOURCE_CONFIG.
  IF TXTP_WEBHOOK_URL IS INITIAL.
    MESSAGE s126(zbdc) DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  "One explicit REST ingest click owns one history session even when the
  "transport or parser rejects the payload.
  PERFORM start_ingest_batch.
  PERFORM make_batch_session USING 1 CHANGING LV_REST_SESSION.
  CONCATENATE 'REST_API://' TXTP_WEBHOOK_URL INTO LV_REST_HIST_PATH.

  CL_HTTP_CLIENT=>CREATE_BY_URL( EXPORTING URL = TXTP_WEBHOOK_URL IMPORTING CLIENT = LO_CLIENT EXCEPTIONS OTHERS = 1 ).
  IF SY-SUBRC <> 0 OR LO_CLIENT IS INITIAL.
    PERFORM p1_save_rejected_unit
      USING LV_REST_SESSION 'REST'
            LV_REST_HIST_PATH
            'REST HTTP client could not be created.'.
    PERFORM finish_ingest_batch.
    COMMIT WORK AND WAIT.
    MESSAGE e127(zbdc).
    RETURN.
  ENDIF.

  LO_CLIENT->REQUEST->SET_METHOD( 'GET' ).
  LO_CLIENT->SEND( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RECEIVE( EXCEPTIONS OTHERS = 1 ).
  LO_CLIENT->RESPONSE->GET_STATUS( IMPORTING CODE = LV_CODE REASON = LV_REASON ).

  IF LV_CODE = 200.
    LV_REST_XSTR = LO_CLIENT->RESPONSE->GET_DATA( ).
    LV_RESP = LO_CLIENT->RESPONSE->GET_CDATA( ).
    SPLIT LV_RESP AT CL_ABAP_CHAR_UTILITIES=>NEWLINE INTO TABLE LT_RAW.
    TXTP_FILE_PATH = 'REST_API://' && TXTP_WEBHOOK_URL.
    LV_SIZE = XSTRLEN( LV_REST_XSTR ).
    PERFORM format_file_size USING LV_SIZE CHANGING TXTP_FILE_SIZE.

    REFRESH GT_STAGING.
    GV_FORCED_SESSION_ID = LV_REST_SESSION.
    PERFORM PROCESS_CSV_ROWS USING LT_RAW.
    CLEAR GV_FORCED_SESSION_ID.
    PERFORM finish_ingest_batch.
    IF GT_STAGING IS NOT INITIAL.
      MODIFY ZBDC_STAGING_BUP FROM TABLE GT_STAGING.

      DATA: LS_REST_META TYPE TY_FILES_DISP.
      READ TABLE GT_STAGING INTO DATA(LS_STG_RT) INDEX 1.
      LS_REST_META-FILE_NAME   = TXTP_FILE_PATH.
      LS_REST_META-FILE_SIZE   = TXTP_FILE_SIZE.
      LS_REST_META-ROWS_LOADED = LINES( GT_STAGING ).
      LS_REST_META-CHANNEL     = 'REST_API'.
      PERFORM get_demo_now CHANGING LS_REST_META-UPLOAD_DATE LS_REST_META-UPLOAD_TIME.
      LS_REST_META-USERNAME    = SY-UNAME.
      LS_REST_META-SESSION_ID  = LS_STG_RT-SESSION_ID.
      APPEND LS_REST_META TO GT_FILES_PREVIEW.
      PERFORM save_ingestion_source_log USING LS_STG_RT-SESSION_ID 'REST' TXTP_FILE_PATH.
      PERFORM update_session_summary USING LS_STG_RT-SESSION_ID.
      PERFORM register_current_session USING LS_STG_RT-SESSION_ID.

      COMMIT WORK AND WAIT.

 "SENIOR FIX: bao dung so dong thuc te, dong bo voi cac kenh khac.
      WRITE LINES( GT_STAGING ) TO TXTP_ROW_COUNT LEFT-JUSTIFIED.
    MESSAGE s128(zbdc) WITH LS_REST_META-ROWS_LOADED.
    ELSE.
 "A transport-success/parser-reject is still one real upload attempt.
      CLEAR TXTP_ROW_COUNT.
      IF gv_ingest_error_msg IS INITIAL.
        gv_ingest_error_msg = 'REST payload returned no accepted staging rows.'.
      ENDIF.
      PERFORM p1_save_rejected_unit
        USING LV_REST_SESSION 'REST' TXTP_FILE_PATH gv_ingest_error_msg.
      COMMIT WORK AND WAIT.
      MESSAGE s129(zbdc) DISPLAY LIKE 'E'.
    ENDIF.
  ELSE.
    LV_REST_REJECT_REASON =
      |REST request rejected with HTTP { LV_CODE }.|.
    PERFORM p1_save_rejected_unit
      USING LV_REST_SESSION 'REST'
            LV_REST_HIST_PATH
            LV_REST_REJECT_REASON.
    PERFORM finish_ingest_batch.
    COMMIT WORK AND WAIT.
    MESSAGE s130(zbdc) WITH LV_CODE DISPLAY LIKE 'E'.
  ENDIF.
  LO_CLIENT->CLOSE( ).
ENDFORM.

"& M123 MERGE HELPERS - Gmail webhook bridge + robust CSV + config mode

FORM LOAD_SOURCE_CONFIG.
  DATA: lt_config TYPE STANDARD TABLE OF zbdc_config_bup,
        ls_config TYPE zbdc_config_bup,
        lv_val    TYPE string,
        lv_timeout TYPE string,
        lv_exec_canon TYPE string,
        lv_exec       TYPE char30,
        lv_mode_raw   TYPE string,
        lv_upd_raw    TYPE string,
        lv_mode       TYPE char1,
        lv_update     TYPE char1,
        lv_mode_norm  TYPE string,
        lv_upd_norm   TYPE string,
        lv_policy_ok  TYPE abap_bool,
        lv_policy_msg TYPE string,
        lv_recovery_msg TYPE string,
        lv_batch_num TYPE i,
        lv_batch_ok TYPE abap_bool,
        lv_batch_msg TYPE string,
        lv_batch_norm TYPE string.

  SELECT * FROM zbdc_config_bup INTO TABLE @lt_config.

 "Configuration load is intentionally read-only and bounded. It may fill
 "global runtime/connector settings, but it must never select an inbound
 "source, TCODE, file path, session, profile, version, script, or mapping
 "context. Those belong to the current upload/onboarding transaction.
  CLEAR txtp_api_key.

  LOOP AT lt_config INTO ls_config.
    lv_val = ls_config-config_value.
    CASE ls_config-config_key.
      WHEN 'SOURCE_TYPE' OR 'TRANSACTION' OR 'FORMAT' OR 'FILE_PATH'
        OR 'GDRIVE_URL'.
 "Legacy context keys ignored by design.
      WHEN 'API_KEY' OR 'GDRIVE_API_KEY'.
 "Legacy plaintext credential keys ignored by design.
      WHEN 'WEBHOOK_URL'.
        txtp_webhook_url = lv_val.
      WHEN 'AUTH_TYPE'.
        p_auth_type = lv_val.
      WHEN 'GDRIVE_AUTH_TYPE'.
        IF p_auth_type IS INITIAL AND lv_val IS NOT INITIAL.
          p_auth_type = lv_val.
        ENDIF.
      WHEN 'TIMEOUT'.
        lv_timeout = lv_val.
      WHEN 'RETRY_ENABLED'.
        chkp_retry = lv_val.
      WHEN 'GDRIVE_SCRIPT_URL'.
        txtp_gdrive_url = lv_val.
      WHEN 'GDRIVE_FOLDER'.
 "Folder defaults are connector metadata; actual Drive file identity
 "is resolved per request and logged in the upload/session evidence.
      WHEN 'BDC_MODE'.
        lv_mode_raw = lv_val.
      WHEN 'BDC_UPDATE'.
        lv_upd_raw = lv_val.
      WHEN 'BDC_EXEC_MODE'.
        lv_exec_canon = lv_val.
      WHEN 'BDC_PROCESS_MODE' OR 'BDC_EXECUTION_MODE'.
        IF lv_exec_canon IS INITIAL.
          lv_exec_canon = lv_val.
        ENDIF.
      WHEN 'BATCH_SIZE'.
        txtp_batch_size = lv_val.
      WHEN 'CONN_STATUS'.
        gv_runtime_last_stat = lv_val.
      WHEN 'CONN_AT'.
        gv_runtime_last_at = lv_val.
      WHEN 'CONN_MSG'.
        gv_runtime_last_msg = lv_val.
    ENDCASE.
  ENDLOOP.

  IF lv_exec_canon IS INITIAL.
    lv_exec = gc_mode_call.
  ELSE.
    lv_exec = lv_exec_canon.
  ENDIF.

  PERFORM canon_exec_mode
    USING    lv_exec
    CHANGING p_bdc_mode lv_policy_ok lv_policy_msg.
  IF lv_policy_ok <> abap_true.
    lv_recovery_msg = lv_policy_msg.
    p_bdc_mode = gc_mode_call.
  ENDIF.

  lv_mode_norm = lv_mode_raw.
  TRANSLATE lv_mode_norm TO UPPER CASE.
  CONDENSE lv_mode_norm NO-GAPS.
  IF lv_mode_norm IS INITIAL.
    lv_mode = 'N'.
  ELSEIF lv_mode_norm = 'N' OR lv_mode_norm = 'E' OR lv_mode_norm = 'A'.
    lv_mode = lv_mode_norm.
  ELSE.
    IF lv_recovery_msg IS INITIAL.
      lv_recovery_msg = |Unsupported persisted BDC mode "{ lv_mode_raw }".|.
    ENDIF.
    lv_mode = 'N'.
  ENDIF.

  lv_upd_norm = lv_upd_raw.
  TRANSLATE lv_upd_norm TO UPPER CASE.
  CONDENSE lv_upd_norm NO-GAPS.
  IF lv_upd_norm IS INITIAL.
    lv_update = 'S'.
  ELSEIF lv_upd_norm = 'S' OR lv_upd_norm = 'A'.
    lv_update = lv_upd_norm.
  ELSE.
    IF lv_recovery_msg IS INITIAL.
      lv_recovery_msg = |Unsupported persisted update mode "{ lv_upd_raw }".|.
    ENDIF.
    lv_update = 'S'.
  ENDIF.

  CLEAR: lv_policy_ok, lv_policy_msg.
  PERFORM apply_policy_state
    USING    p_bdc_mode lv_mode lv_update
    CHANGING lv_policy_ok lv_policy_msg.
  IF lv_policy_ok <> abap_true.
    MESSAGE lv_policy_msg TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  IF txtp_batch_size IS INITIAL.
    txtp_batch_size = '100'.
  ELSE.
    PERFORM parse_pos_int
      USING    txtp_batch_size 'Persisted batch size'
      CHANGING lv_batch_num lv_batch_ok lv_batch_msg lv_batch_norm.
    IF lv_batch_ok = abap_true.
      txtp_batch_size = lv_batch_norm.
    ELSE.
      IF lv_recovery_msg IS INITIAL.
        lv_recovery_msg = lv_batch_msg.
      ENDIF.
      txtp_batch_size = '100'.
    ENDIF.
  ENDIF.

  IF lv_timeout IS INITIAL.
    txtp_timeout = 60.
  ELSE.
    CONDENSE lv_timeout NO-GAPS.
    TRY.
        txtp_timeout = lv_timeout.
      CATCH cx_root INTO DATA(lx_timeout).
        IF lv_recovery_msg IS INITIAL.
          lv_recovery_msg = lx_timeout->get_text( ).
        ENDIF.
        txtp_timeout = 60.
    ENDTRY.
    IF txtp_timeout < 1 OR txtp_timeout > 300.
      IF lv_recovery_msg IS INITIAL.
        lv_recovery_msg = 'Persisted timeout must be between 1 and 300 seconds.'.
      ENDIF.
      txtp_timeout = 60.
    ENDIF.
  ENDIF.

  IF lv_recovery_msg IS NOT INITIAL.
 "do not spam 0300 with a warning on every entry when an old
 "config row contains an invalid timeout/batch value. The visible fields
 "are normalized for this runtime; Save persists them through the bounded
 "config service. No upload/source/session context is changed here.
    CLEAR lv_recovery_msg.
  ENDIF.
ENDFORM.

FORM SELECT_INBOUND_CHANNEL.
 "single-select source chooser.
 "POPUP_TO_DECIDE_LIST shows Select All / Deselect All because it is a
 "multi-checkbox popup. For inbound source we need exactly one choice, so
 "use F4IF_INT_TABLE_VALUE_REQUEST with MULTIPLE_CHOICE = SPACE.
  TYPES: BEGIN OF TY_SOURCE_CHOICE,
           SOURCE_CODE TYPE C LENGTH 10,
           SOURCE_TEXT TYPE C LENGTH 60,
         END OF TY_SOURCE_CHOICE.

  DATA: LT_SOURCE   TYPE STANDARD TABLE OF TY_SOURCE_CHOICE,
        LS_SOURCE   TYPE TY_SOURCE_CHOICE,
        LT_FIELDTAB TYPE STANDARD TABLE OF DFIES,
        LS_FIELDTAB TYPE DFIES,
        LT_RETURN   TYPE STANDARD TABLE OF DDSHRETVAL,
        LS_RETURN   TYPE DDSHRETVAL,
        LV_CHOICE   TYPE C LENGTH 80.

  CLEAR LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'LOCAL'.
  LS_SOURCE-SOURCE_TEXT = 'Local File Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'GDRIVE'.
  LS_SOURCE-SOURCE_TEXT = 'Google Drive Cloud Ingestion'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_SOURCE.
  LS_SOURCE-SOURCE_CODE = 'REST'.
  LS_SOURCE-SOURCE_TEXT = 'Gmail Data Entry Submissions'.
  APPEND LS_SOURCE TO LT_SOURCE.

  CLEAR LS_FIELDTAB.
  LS_FIELDTAB-FIELDNAME = 'SOURCE_CODE'.
  LS_FIELDTAB-REPTEXT   = 'Source Code'.
  LS_FIELDTAB-SCRTEXT_L = 'Source Code'.
  LS_FIELDTAB-FIELDTEXT = 'Source Code'.
  LS_FIELDTAB-DATATYPE  = 'CHAR'.
  LS_FIELDTAB-INTTYPE   = 'C'.
  LS_FIELDTAB-INTLEN    = 10.
  LS_FIELDTAB-OUTPUTLEN = 10.
  APPEND LS_FIELDTAB TO LT_FIELDTAB.

  CLEAR LS_FIELDTAB.
  LS_FIELDTAB-FIELDNAME = 'SOURCE_TEXT'.
  LS_FIELDTAB-REPTEXT   = 'Channel Description'.
  LS_FIELDTAB-SCRTEXT_L = 'Channel Description'.
  LS_FIELDTAB-FIELDTEXT = 'Channel Description'.
  LS_FIELDTAB-DATATYPE  = 'CHAR'.
  LS_FIELDTAB-INTTYPE   = 'C'.
  LS_FIELDTAB-INTLEN    = 60.
  LS_FIELDTAB-OUTPUTLEN = 45.
  APPEND LS_FIELDTAB TO LT_FIELDTAB.

  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      RETFIELD        = 'SOURCE_CODE'
      DYNPPROG        = SY-REPID
      DYNPNR          = SY-DYNNR
      WINDOW_TITLE    = 'Browse Inbound Source'
      VALUE_ORG       = 'S'
      MULTIPLE_CHOICE = SPACE
    TABLES
      VALUE_TAB       = LT_SOURCE
      FIELD_TAB       = LT_FIELDTAB
      RETURN_TAB      = LT_RETURN
    EXCEPTIONS
      PARAMETER_ERROR = 1
      NO_VALUES_FOUND = 2
      OTHERS          = 3.

  IF SY-SUBRC <> 0.
    RETURN.
  ENDIF.

  CLEAR LV_CHOICE.
  READ TABLE LT_RETURN INTO LS_RETURN INDEX 1.
  IF SY-SUBRC = 0.
    LV_CHOICE = LS_RETURN-FIELDVAL.
  ENDIF.

  IF LV_CHOICE IS INITIAL.
    RETURN.
  ENDIF.

  TRANSLATE LV_CHOICE TO UPPER CASE.
  CONDENSE LV_CHOICE.

  IF LV_CHOICE CS 'GDRIVE' OR LV_CHOICE = 'GDRIV' OR LV_CHOICE = 'GD' OR LV_CHOICE CS 'GOOGLE'.
    LV_CHOICE = 'GDRIVE'.
  ELSEIF LV_CHOICE CS 'LOCAL'.
    LV_CHOICE = 'LOCAL'.
  ELSEIF LV_CHOICE CS 'REST' OR LV_CHOICE CS 'EMAIL' OR LV_CHOICE CS 'MAIL'.
    LV_CHOICE = 'REST'.
  ENDIF.

  CASE LV_CHOICE.
    WHEN 'LOCAL'.
      PERFORM BROWSE_FILE.

    WHEN 'GDRIVE' OR 'GDRIV' OR 'GD'.
 "Browse is selection-only for every inbound source. Google Drive may perform
 "OAuth/listing metadata work here, but it must not create staging.
      PERFORM SELECT_GDRIVE_FILE_PATH.

    WHEN 'REST'.
 "Gmail Browse pulls pending requests and stores the exact user selection in
 "memory only. Upload/Ingest is the sole boundary that creates staging rows.
      PERFORM browse_gmail_pending.

    WHEN OTHERS.
    MESSAGE s133(zbdc) WITH LV_CHOICE DISPLAY LIKE 'W'.
  ENDCASE.
ENDFORM.

*&---------------------------------------------------------------------*
*& Canonical file-content fingerprint from the exact staged inbound rows.
*& Volatile lifecycle/audit fields are excluded so re-uploading the same
*& business content under a new session produces the same SHA-256 fingerprint.
*&---------------------------------------------------------------------*
FORM build_ingestion_content_hash
  USING    iv_session_id TYPE zbdc_staging_bup-session_id
  CHANGING cv_hash       TYPE zbdc_file_lg_bup-file_hash
           cv_ok         TYPE abap_bool
           cv_message    TYPE string.

  DATA: lt_stg      TYPE STANDARD TABLE OF zbdc_staging_bup,
        ls_stg      TYPE zbdc_staging_bup,
        lo_desc     TYPE REF TO cl_abap_structdescr,
        lt_comp     TYPE abap_component_tab,
        ls_comp     LIKE LINE OF lt_comp,
        lv_payload  TYPE string,
        lv_value    TYPE string,
        lv_name     TYPE string,
        lv_hash64   TYPE string.
  FIELD-SYMBOLS <fv> TYPE any.

  CLEAR: cv_hash, cv_ok, cv_message.
  SELECT * FROM zbdc_staging_bup INTO TABLE @lt_stg
    WHERE session_id = @iv_session_id.
  IF lt_stg IS INITIAL.
    cv_message = 'No staged inbound rows exist for content hashing.'.
    RETURN.
  ENDIF.
  SORT lt_stg BY row_index record_key.

  lo_desc ?= cl_abap_typedescr=>describe_by_data( ls_stg ).
  lt_comp = lo_desc->get_components( ).

  LOOP AT lt_stg INTO ls_stg.
    lv_payload = lv_payload && |#ROW={ ls_stg-row_index };|.
    LOOP AT lt_comp INTO ls_comp.
      lv_name = ls_comp-name.
      TRANSLATE lv_name TO UPPER CASE.
      IF lv_name = 'SESSION_ID' OR lv_name = 'STATUS' OR
         lv_name = 'ERROR_MSG' OR lv_name = 'LAST_ERROR' OR
         lv_name = 'CREATED_AT' OR lv_name = 'CREATED_BY' OR
         lv_name = 'UPDATED_AT' OR lv_name = 'UPDATED_BY' OR
         lv_name = 'SOURCE_FILE' OR lv_name = 'FILE_NAME' OR
         lv_name = 'SHEET_NAME' OR lv_name = 'BATCH_KEY'.
        CONTINUE.
      ENDIF.
      ASSIGN COMPONENT ls_comp-name OF STRUCTURE ls_stg TO <fv>.
      IF sy-subrc <> 0. CONTINUE. ENDIF.
      CLEAR lv_value.
      TRY.
          lv_value = |{ <fv> }|.
        CATCH cx_root.
          CONTINUE.
      ENDTRY.
      lv_payload = lv_payload && |{ lv_name }={ lv_value };|.
    ENDLOOP.
  ENDLOOP.

  TRY.
      cl_abap_message_digest=>calculate_hash_for_char(
        EXPORTING if_algorithm = 'SHA-256' if_data = lv_payload
        IMPORTING ef_hashb64string = lv_hash64 ).
    CATCH cx_abap_message_digest INTO DATA(lx_hash).
      cv_message = lx_hash->get_text( ).
      RETURN.
  ENDTRY.
  IF lv_hash64 IS INITIAL.
    cv_message = 'SHA-256 content fingerprint could not be calculated.'.
    RETURN.
  ENDIF.
  cv_hash = lv_hash64.
  cv_ok = abap_true.
ENDFORM.

FORM save_ingestion_source_log
  USING iv_session_id TYPE zbdc_result_bup-session_id
        iv_source     TYPE char20
        iv_file       TYPE csequence.

  DATA: lv_file_str TYPE string,
        ls_res      TYPE zbdc_result_bup,
        ls_sess_src TYPE zbdc_session_bup,
        ls_file_lg  TYPE zbdc_file_lg_bup,
        lv_ts       TYPE tzntstmps,
        lv_msg      TYPE zbdc_result_bup-message,
        lv_hash         TYPE zbdc_file_lg_bup-file_hash,
        lv_rows         TYPE zbdc_file_lg_bup-row_count,
        lv_p_at         TYPE zbdc_file_lg_bup-processed_at,
        lv_demo_date_836 TYPE sy-datum,
        lv_demo_time_836 TYPE sy-uzeit,
        lv_hash_ok       TYPE abap_bool,
        lv_hash_msg      TYPE string,
        lv_dup_session   TYPE zbdc_file_lg_bup-session_id,
        lv_contract_ok  TYPE abap_bool,
        lv_contract_msg TYPE string,
        lv_contract_err TYPE zbdc_staging_bup-error_msg,
        ls_contract_res TYPE zbdc_result_bup.

  FIELD-SYMBOLS <ls_contract_stg> TYPE zbdc_staging_bup.

  IF iv_session_id IS INITIAL OR iv_source IS INITIAL.
    RETURN.
  ENDIF.

  lv_file_str = iv_file.
  GET TIME STAMP FIELD lv_ts.

  CONCATENATE 'TCODE=' p_transaction
              ';PROFILE=' txtp_profile_name
              ';VERSION=' gv_profile_ver
              ';INBOUND_SOURCE=' iv_source
              ';SIZE=' txtp_file_size
              ';USER=' sy-uname
              ';FILE=' lv_file_str
         INTO lv_msg.

  CLEAR ls_res.
  ls_res-session_id  = iv_session_id.
  ls_res-row_index   = 0.
  ls_res-record_key  = '__SOURCE__'.
  ls_res-tcode       = p_transaction.
  ls_res-msg_type    = 'I'.
  ls_res-message     = lv_msg.
  ls_res-exec_status = 'INFO'.
  ls_res-created_at  = lv_ts.
  ls_res-step        = 0.

  INSERT zbdc_result_bup FROM ls_res.
  IF sy-subrc <> 0.
    MODIFY zbdc_result_bup FROM ls_res.
  ENDIF.

 "File history source of truth for Screen 0302 Preview Files.
 "ZBDC_FILE_LG_BUP structure in this system:
 "FILE_HASH, FILE_NAME, SOURCE, ROW_COUNT, SESSION_ID, PROCESSED_AT, STATUS, ERROR_MSG.
  SELECT COUNT(*)
    FROM zbdc_staging_bup
    INTO @lv_rows
    WHERE session_id = @iv_session_id.

  PERFORM get_demo_now CHANGING lv_demo_date_836 lv_demo_time_836.
  CONCATENATE lv_demo_date_836 lv_demo_time_836 INTO lv_p_at.

  CLEAR: lv_hash, lv_hash_ok, lv_hash_msg, lv_dup_session.
  PERFORM build_ingestion_content_hash
    USING    iv_session_id
    CHANGING lv_hash lv_hash_ok lv_hash_msg.
  IF lv_hash_ok <> abap_true OR lv_hash IS INITIAL.
    lv_contract_err = |CONTENT_HASH_FAILED: { lv_hash_msg }|.
    UPDATE zbdc_staging_bup SET status = @gc_st_error, error_msg = @lv_contract_err
      WHERE session_id = @iv_session_id.
    LOOP AT gt_staging ASSIGNING <ls_contract_stg> WHERE session_id = iv_session_id.
      <ls_contract_stg>-status = gc_st_error.
      <ls_contract_stg>-error_msg = lv_contract_err.
    ENDLOOP.
    MESSAGE lv_contract_err TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  SELECT SINGLE session_id FROM zbdc_file_lg_bup INTO @lv_dup_session
    WHERE file_hash = @lv_hash
      AND session_id <> @iv_session_id
      AND status = 'IMPORTED'.
  IF sy-subrc = 0 AND lv_dup_session IS NOT INITIAL.
    lv_contract_err = |DUPLICATE_CONTENT: identical canonical inbound content was already imported in session { lv_dup_session }.|.
    UPDATE zbdc_staging_bup SET status = @gc_st_error, error_msg = @lv_contract_err
      WHERE session_id = @iv_session_id.
    LOOP AT gt_staging ASSIGNING <ls_contract_stg> WHERE session_id = iv_session_id.
      <ls_contract_stg>-status = gc_st_error.
      <ls_contract_stg>-error_msg = lv_contract_err.
    ENDLOOP.
    CLEAR ls_file_lg.
    ls_file_lg-file_hash    = lv_hash.
    ls_file_lg-file_name    = lv_file_str.
    ls_file_lg-source       = iv_source.
    ls_file_lg-row_count    = lv_rows.
    ls_file_lg-session_id   = iv_session_id.
    ls_file_lg-processed_at = lv_p_at.
    ls_file_lg-status       = 'ERROR'.
    ls_file_lg-error_msg    = lv_contract_err.
    INSERT zbdc_file_lg_bup FROM ls_file_lg.
    MESSAGE lv_contract_err TYPE 'S' DISPLAY LIKE 'E'.
    RETURN.
  ENDIF.

  CLEAR ls_file_lg.
  ls_file_lg-file_hash    = lv_hash.
  ls_file_lg-file_name    = lv_file_str.
  ls_file_lg-source       = iv_source.
  ls_file_lg-row_count    = lv_rows.
  ls_file_lg-session_id   = iv_session_id.
  ls_file_lg-processed_at = lv_p_at.
  ls_file_lg-status       = 'IMPORTED'.
  CLEAR ls_file_lg-error_msg.

  INSERT zbdc_file_lg_bup FROM ls_file_lg.
  IF sy-subrc <> 0.
    MODIFY zbdc_file_lg_bup FROM ls_file_lg.
  ENDIF.

 "atomically bind this upload session to the exact resolved contract.
 "This is generic for every TCODE/profile and prevents validation/execution
 "from falling back to a later or unrelated active version.
  CLEAR: lv_contract_ok, lv_contract_msg.
  PERFORM freeze_session_contract
    USING    iv_session_id
    CHANGING lv_contract_ok lv_contract_msg.

  IF lv_contract_ok <> abap_true.
    lv_contract_err = lv_contract_msg.

    UPDATE zbdc_file_lg_bup
      SET status    = 'ERROR',
          error_msg = @lv_contract_err
      WHERE file_hash = @lv_hash.

    UPDATE zbdc_staging_bup
      SET status    = @gc_st_error,
          error_msg = @lv_contract_err
      WHERE session_id = @iv_session_id.

 "keep the in-memory staging copy consistent with the persisted rows.
 "Without this, Screen 0400 re-validates stale STAGED rows and hides the real
 "freeze failure behind the generic 'missing frozen contract' message.
    LOOP AT gt_staging ASSIGNING <ls_contract_stg>
      WHERE session_id = iv_session_id.
      <ls_contract_stg>-status    = gc_st_error.
      <ls_contract_stg>-error_msg = lv_contract_err.
    ENDLOOP.

    CLEAR ls_contract_res.
    ls_contract_res-session_id  = iv_session_id.
    ls_contract_res-row_index   = 0.
    ls_contract_res-record_key  = '__CONTRACT__'.
    ls_contract_res-tcode       = p_transaction.
    ls_contract_res-msg_type    = 'E'.
    ls_contract_res-message     = lv_contract_msg.
    ls_contract_res-exec_status = 'ERROR'.
    ls_contract_res-created_at  = lv_ts.
    ls_contract_res-step        = 0.
    INSERT zbdc_result_bup FROM ls_contract_res.
    IF sy-subrc <> 0.
      MODIFY zbdc_result_bup FROM ls_contract_res.
    ENDIF.
  ENDIF.

 "Strict-real creator evidence: ZBDC_RESULT_BUP has no CREATED_BY field in
 "this system, so persist the real upload user in the session summary table.
  CLEAR ls_sess_src.
  SELECT SINGLE *
    FROM zbdc_session_bup
    INTO @ls_sess_src
    WHERE session_id = @iv_session_id.

  IF sy-subrc <> 0.
    CLEAR ls_sess_src.
    ls_sess_src-session_id = iv_session_id.
    ls_sess_src-start_time = lv_ts.
  ELSEIF ls_sess_src-start_time IS INITIAL.
    ls_sess_src-start_time = lv_ts.
  ENDIF.

  IF ls_sess_src-created_by IS INITIAL OR ls_sess_src-created_by = 'UNKNOWN'.
    ls_sess_src-created_by = sy-uname.
  ENDIF.

  MODIFY zbdc_session_bup FROM ls_sess_src.

ENDFORM.

"& update_session_summary
"& Rebuild ZBDC_SESSION_BUP from real staging + result logs.
"& This makes Main Dashboard KPI and SE16N proof complete.

FORM clear_0300_after_browse.
 "Selecting a new source/file means the old preview is no longer current.
 "This is a browse-only reset: do not delete DB history, only clear the
 "current in-memory upload preview and all counters on screen 0300.
  REFRESH: gt_staging, gt_staging_alv, gt_errors, gt_preview_data,
           gt_current_sessions, gt_preview_src_cache, gt_preview_hdr_cache.
  CLEAR: txtp_row_count, txtp_row, txtp_rows, txtp_loaded, txtp_rows_loaded,
         txtp_loaded_rows, txtgv_row_count, txtgv_rows, txtgv_loaded,
         txtgv_total_rows, txtgv_tot_rows,
         gv_current_batch_prefix, gv_ingest_batch_prefix, gv_forced_session_id,
         gv_current_batch_count, gv_current_file_name, gv_current_sheet_name,
         gv_current_unit_src, gv_ingest_error_msg.
  FREE MEMORY ID 'ZBDC_0300_HISTORY_SCOPE'.
  txtp_file_size = '0 B'.
  PERFORM set_row_count_fields USING 0.
  g_sub_dynpro = '0301'.
  ts_preview-activetab = 'TAB_PREVIEW'.

 "If the 0301 ALV already exists, refresh it immediately so a new Browse
 "does not keep showing rows from the previous upload until the next screen.
  REFRESH gt_preview_data.
  IF go_alv_0301 IS BOUND.
    DATA ls_stable_browse TYPE lvc_s_stbl.
    ls_stable_browse-row = abap_true.
    ls_stable_browse-col = abap_true.
    CALL METHOD go_alv_0301->refresh_table_display
      EXPORTING
        is_stable      = ls_stable_browse
        i_soft_refresh = abap_false.
  ENDIF.

 "Force SALV 0301 to be rebuilt empty. RESET_0300_ALV intentionally keeps
 "0301 alive during normal upload refresh, but Browse needs a hard reset
 "so old rows are not visually reused.
  PERFORM reset_0300_all_alv.
ENDFORM.
