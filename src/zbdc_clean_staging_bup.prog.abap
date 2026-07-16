REPORT zbdc_clean_staging_bup.

PARAMETERS: p_stg AS CHECKBOX DEFAULT 'X',   " xoa ZBDC_STAGING
            p_log AS CHECKBOX DEFAULT 'X',   " xoa ZBDC_FILE_LOG
            p_res AS CHECKBOX DEFAULT ' '.   " xoa ZBDC_RESULT (tu chon)

START-OF-SELECTION.
  DATA lv_ans TYPE c.
  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      titlebar      = 'Xac nhan xoa data'
      text_question = 'Xoa sach cac bang da tick? Khong the hoan tac.'
      text_button_1 = 'Xoa'
      text_button_2 = 'Huy'
    IMPORTING
      answer        = lv_ans.
  IF lv_ans <> '1'. WRITE: / 'Da huy.'. RETURN. ENDIF.

  IF p_stg = 'X'.
    DELETE FROM zbdc_staging.
    WRITE: / |ZBDC_STAGING: da xoa { sy-dbcnt } dong.|.
  ENDIF.
  IF p_log = 'X'.
    DELETE FROM zbdc_file_log.
    WRITE: / |ZBDC_FILE_LOG: da xoa { sy-dbcnt } dong.|.
  ENDIF.
  IF p_res = 'X'.
    DELETE FROM zbdc_result.
    WRITE: / |ZBDC_RESULT: da xoa { sy-dbcnt } dong.|.
  ENDIF.
  COMMIT WORK.
  WRITE: / 'Xong. Data da sach.'.
