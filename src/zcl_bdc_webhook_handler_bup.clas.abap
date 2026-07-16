class ZCL_BDC_WEBHOOK_HANDLER_BUP definition
  public
  create public .

public section.

  interfaces IF_HTTP_EXTENSION .
protected section.
private section.
ENDCLASS.



CLASS ZCL_BDC_WEBHOOK_HANDLER_BUP IMPLEMENTATION.


METHOD IF_HTTP_EXTENSION~HANDLE_REQUEST.

  DATA: lv_body  TYPE string,
        lv_resp  TYPE string,
        lv_id    TYPE zbdc_mail_inbox-inbox_id,
        ls_inbox TYPE zbdc_mail_inbox,
        lv_guid  TYPE guid_32,
        lv_exist TYPE zbdc_mail_inbox-inbox_id.

  TYPES: BEGIN OF ty_payload,
           message_id TYPE string,
           sender     TYPE string,
           mail_time  TYPE string,
           subject    TYPE string,
           filename   TYPE string,
           content    TYPE string,
         END OF ty_payload.

  DATA: ls_payload TYPE ty_payload.

  " 1. Đọc body JSON từ n8n
  lv_body = server->request->get_cdata( ).

  IF lv_body IS INITIAL.
    server->response->set_status( code = 400 reason = 'Bad Request' ).
    server->response->set_header_field( name = 'Content-Type' value = 'application/json' ).
    server->response->set_cdata( '{"status":"error","msg":"empty body"}' ).
    RETURN.
  ENDIF.

  " 2. Parse JSON
  /ui2/cl_json=>deserialize(
    EXPORTING json = lv_body pretty_name = /ui2/cl_json=>pretty_mode-camel_case
    CHANGING  data = ls_payload ).

  IF ls_payload-filename IS INITIAL AND ls_payload-content IS INITIAL.
    server->response->set_status( code = 400 reason = 'Bad Request' ).
    server->response->set_header_field( name = 'Content-Type' value = 'application/json' ).
    server->response->set_cdata( '{"status":"error","msg":"invalid payload"}' ).
    RETURN.
  ENDIF.

  " 2b. ===== IDEMPOTENCY TẦNG TRANSPORT: check Message-ID =====
  IF ls_payload-message_id IS NOT INITIAL.
    SELECT SINGLE inbox_id INTO lv_exist
      FROM zbdc_mail_inbox
      WHERE message_id = ls_payload-message_id.

    IF sy-subrc = 0.
      server->response->set_status( code = 200 reason = 'OK' ).
      server->response->set_header_field( name = 'Content-Type' value = 'application/json' ).
      lv_resp = |{ '{' }"status":"skipped","reason":"duplicate_email","inbox_id":"{ lv_exist }"{ '}' }|.
      server->response->set_cdata( lv_resp ).
      RETURN.
    ENDIF.
  ENDIF.

  " 3. Sinh INBOX_ID (GUID)
  CALL FUNCTION 'GUID_CREATE'
    IMPORTING ev_guid_32 = lv_guid.
  lv_id = lv_guid.

  " 4. Ghi ZBDC_MAIL_INBOX
  CLEAR ls_inbox.
  ls_inbox-inbox_id     = lv_id.
  ls_inbox-message_id   = ls_payload-message_id.
  ls_inbox-sender       = ls_payload-sender.
  ls_inbox-mail_time    = ls_payload-mail_time.
  ls_inbox-subject      = ls_payload-subject.
  ls_inbox-file_name    = ls_payload-filename.
  ls_inbox-file_content = ls_payload-content.
  ls_inbox-status       = 'NEW'.
  GET TIME STAMP FIELD ls_inbox-created_at.

  INSERT zbdc_mail_inbox FROM ls_inbox.

  IF sy-subrc = 0.
    COMMIT WORK.
    lv_resp = |{ '{' }"status":"success","inbox_id":"{ lv_id }","file":"{ ls_payload-filename }"{ '}' }|.
    server->response->set_status( code = 200 reason = 'OK' ).
  ELSE.
    ROLLBACK WORK.
    lv_resp = '{"status":"error","msg":"db insert failed"}'.
    server->response->set_status( code = 500 reason = 'Error' ).
  ENDIF.

  server->response->set_header_field( name = 'Content-Type' value = 'application/json' ).
  server->response->set_cdata( lv_resp ).

ENDMETHOD.
ENDCLASS.
