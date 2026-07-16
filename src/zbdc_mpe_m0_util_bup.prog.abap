*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M0_UTIL_BUP
*& Purpose          M0 Common Framework - Utility helpers
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM z23_format_file_size - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z23_format_file_size
  USING    pv_bytes TYPE i
  CHANGING cv_text  TYPE char20.

  DATA: lv_value TYPE p LENGTH 12 DECIMALS 1,
        lv_unit  TYPE c LENGTH 2.

  CLEAR cv_text.
  IF pv_bytes < 0.
    cv_text = 'Unknown'.
    RETURN.
  ENDIF.

  IF pv_bytes < 1024.
    WRITE pv_bytes TO cv_text LEFT-JUSTIFIED.
    CONDENSE cv_text.
    CONCATENATE cv_text 'B' INTO cv_text SEPARATED BY space.
    RETURN.
  ENDIF.

  lv_value = pv_bytes.
  IF pv_bytes < 1048576.
    DIVIDE lv_value BY 1024.
    lv_unit = 'KB'.
  ELSE.
    DIVIDE lv_value BY 1048576.
    lv_unit = 'MB'.
  ENDIF.

  WRITE lv_value TO cv_text DECIMALS 1 LEFT-JUSTIFIED.
  CONDENSE cv_text.
  CONCATENATE cv_text lv_unit INTO cv_text SEPARATED BY space.
ENDFORM.
*<<< END FORM z23_format_file_size

*>>> FORM z23_recalc_frontend_size - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP


FORM z23_recalc_frontend_size
  USING    pv_file TYPE any
  CHANGING cv_size TYPE char20.

  DATA: lv_size_check TYPE string,
        lv_file       TYPE string,
        lv_dummy      TYPE string.

  lv_size_check = cv_size.
  TRANSLATE lv_size_check TO UPPER CASE.
  CONDENSE lv_size_check NO-GAPS.

  "Keep trusted non-zero sizes already calculated during ingestion.
  IF cv_size IS NOT INITIAL
     AND lv_size_check <> 'UNKNOWN'
     AND lv_size_check <> '0B'
     AND lv_size_check <> '0.0KB'
     AND lv_size_check <> '0KB'.
    RETURN.
  ENDIF.

  lv_file = pv_file.
  IF lv_file CS '|SHEET='.
    SPLIT lv_file AT '|SHEET=' INTO lv_file lv_dummy.
  ENDIF.
  CONDENSE lv_file.

  IF lv_file IS INITIAL
     OR lv_file CP 'GoogleDrive://*'
     OR lv_file CP 'HTTP://*'
     OR lv_file CP 'HTTPS://*'
     OR lv_file CS ';'.
    IF cv_size IS INITIAL OR lv_size_check = '0B'.
      cv_size = 'Unknown'.
    ENDIF.
    RETURN.
  ENDIF.

  CLEAR gv_z23_file_size_bytes.
  cl_gui_frontend_services=>file_get_size(
    EXPORTING
      file_name = lv_file
    IMPORTING
      file_size = gv_z23_file_size_bytes
    EXCEPTIONS
      OTHERS    = 1 ).
  CALL METHOD cl_gui_cfw=>flush EXCEPTIONS OTHERS = 1.

  IF sy-subrc = 0 AND gv_z23_file_size_bytes > 0.
    PERFORM z23_format_file_size USING gv_z23_file_size_bytes CHANGING cv_size.
  ELSEIF cv_size IS INITIAL OR lv_size_check = '0B'.
    cv_size = 'Unknown'.
  ENDIF.
ENDFORM.
*<<< END FORM z23_recalc_frontend_size

*>>> FORM GET_DYN_COMP_AS_STRING - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM GET_DYN_COMP_AS_STRING USING IS_ANY TYPE ANY IV_COMP TYPE STRING CHANGING CV_VALUE TYPE STRING.
  FIELD-SYMBOLS <V> TYPE ANY.
  CLEAR CV_VALUE.
  ASSIGN COMPONENT IV_COMP OF STRUCTURE IS_ANY TO <V>.
  IF SY-SUBRC = 0 AND <V> IS ASSIGNED.
    CV_VALUE = <V>.
  ENDIF.
ENDFORM.
*<<< END FORM GET_DYN_COMP_AS_STRING

*>>> FORM z16_table_exists - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_table_exists USING iv_tabname TYPE tabname CHANGING cv_exists TYPE abap_bool.
  DATA lt_dfies TYPE STANDARD TABLE OF dfies.
  CLEAR cv_exists.
  CALL FUNCTION 'DDIF_FIELDINFO_GET'
    EXPORTING
      tabname   = iv_tabname
    TABLES
      dfies_tab = lt_dfies
    EXCEPTIONS
      not_found = 1
      OTHERS    = 2.
  IF sy-subrc = 0 AND lt_dfies IS NOT INITIAL.
    cv_exists = abap_true.
  ENDIF.
ENDFORM.
*<<< END FORM z16_table_exists

*>>> FORM z16_get_comp_str - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_get_comp_str USING is_any TYPE any iv_comp TYPE csequence CHANGING cv_value TYPE string.
  FIELD-SYMBOLS <lv_any> TYPE any.
  CLEAR cv_value.
  ASSIGN COMPONENT iv_comp OF STRUCTURE is_any TO <lv_any>.
  IF sy-subrc = 0.
    cv_value = |{ <lv_any> }|.
    CONDENSE cv_value.
  ENDIF.
ENDFORM.
*<<< END FORM z16_get_comp_str

*>>> FORM z16_set_comp_str - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM z16_set_comp_str USING iv_comp TYPE csequence iv_value TYPE any CHANGING cs_any TYPE any.
  FIELD-SYMBOLS <lv_any> TYPE any.
  ASSIGN COMPONENT iv_comp OF STRUCTURE cs_any TO <lv_any>.
  IF sy-subrc = 0.
    <lv_any> = iv_value.
  ENDIF.
ENDFORM.
*<<< END FORM z16_set_comp_str
