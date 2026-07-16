FUNCTION z_bdc_exec_one_bup.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_TCODE) TYPE TCODE
*"     VALUE(IV_UPDMODE) TYPE CHAR1 DEFAULT 'S'
*"  EXPORTING
*"     VALUE(EV_SUBRC) TYPE SYSUBRC
*"     VALUE(EV_MESSAGE) TYPE CHAR255
*"  TABLES
*"      IT_BDCDATA STRUCTURE BDCDATA
*"      ET_BDCMSG STRUCTURE BDCMSGCOLL
*"----------------------------------------------------------------------

  DATA:
    ls_options TYPE ctu_params,
    ls_message TYPE bdcmsgcoll,
    lv_text    TYPE char255,
    lv_lines   TYPE i.

  CLEAR:
    ev_subrc,
    ev_message,
    ls_options.

  REFRESH et_bdcmsg.

  IF iv_tcode IS INITIAL.
    ev_subrc   = 4.
    ev_message = 'Transaction code is required.'.
    RETURN.
  ENDIF.

  IF it_bdcdata[] IS INITIAL.
    ev_subrc   = 4.
    ev_message = 'BDC data is empty.'.
    RETURN.
  ENDIF.

  ls_options-dismode = 'N'.

  IF iv_updmode = 'A'.
    ls_options-updmode = 'A'.
  ELSE.
    ls_options-updmode = 'S'.
  ENDIF.

  ls_options-defsize = 'X'.
  ls_options-nobinpt = 'X'.

  CALL TRANSACTION iv_tcode
    USING         it_bdcdata
    OPTIONS FROM  ls_options
    MESSAGES INTO et_bdcmsg.

  ev_subrc = sy-subrc.

  LOOP AT et_bdcmsg INTO ls_message
       WHERE msgtyp = 'E'
          OR msgtyp = 'A'
          OR msgtyp = 'X'.

    CLEAR lv_text.

    CALL FUNCTION 'FORMAT_MESSAGE'
      EXPORTING
        id        = ls_message-msgid
        lang      = sy-langu
        no        = ls_message-msgnr
        v1        = ls_message-msgv1
        v2        = ls_message-msgv2
        v3        = ls_message-msgv3
        v4        = ls_message-msgv4
      IMPORTING
        msg       = lv_text
      EXCEPTIONS
        not_found = 1
        OTHERS    = 2.

    IF sy-subrc = 0 AND lv_text IS NOT INITIAL.
      ev_message = lv_text.
    ELSE.
      ev_message = 'BDC processing ended with an SAP error.'.
    ENDIF.

    EXIT.
  ENDLOOP.

  IF ev_message IS INITIAL.

    DESCRIBE TABLE et_bdcmsg LINES lv_lines.

    IF lv_lines > 0.

      READ TABLE et_bdcmsg
        INTO ls_message
        INDEX lv_lines.

      IF sy-subrc = 0.

        CLEAR lv_text.

        CALL FUNCTION 'FORMAT_MESSAGE'
          EXPORTING
            id        = ls_message-msgid
            lang      = sy-langu
            no        = ls_message-msgnr
            v1        = ls_message-msgv1
            v2        = ls_message-msgv2
            v3        = ls_message-msgv3
            v4        = ls_message-msgv4
          IMPORTING
            msg       = lv_text
          EXCEPTIONS
            not_found = 1
            OTHERS    = 2.

        IF sy-subrc = 0 AND lv_text IS NOT INITIAL.
          ev_message = lv_text.
        ENDIF.

      ENDIF.
    ENDIF.
  ENDIF.

  IF ev_message IS INITIAL.
    IF ev_subrc = 0.
      ev_message = 'BDC worker completed successfully.'.
    ELSE.
      ev_message =
        'BDC worker finished without a readable SAP message.'.
    ENDIF.
  ENDIF.

ENDFUNCTION.
