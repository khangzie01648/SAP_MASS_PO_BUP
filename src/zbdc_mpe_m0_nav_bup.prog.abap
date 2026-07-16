*&---------------------------------------------------------------------*
*& Include          ZBDC_MPE_M0_NAV_BUP
*& Purpose          M0 Common Framework - Screen navigation, dispatcher, common UI
*& Source split     FIX16 V5BR - logic moved from F01
*&---------------------------------------------------------------------*

*>>> FORM BUILD_0200_CFG_SIG - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP



FORM BUILD_0200_CFG_SIG CHANGING CV_SIG TYPE STRING.
  DATA: LV_MODE    TYPE CHAR1,
        LV_UPD     TYPE CHAR1,
        LV_BSZ     TYPE CHAR10,
        LV_HOST    TYPE CHAR60,
        LV_PORT    TYPE CHAR10,
        LV_EXEC    TYPE CHAR30,
        LV_RETRY   TYPE CHAR1,
        LV_TIMEOUT TYPE CHAR20.

  IF RB_MODE_N = 'X'.
    LV_MODE = 'N'.
  ELSEIF RB_MODE_E = 'X'.
    LV_MODE = 'E'.
  ELSEIF RB_MODE_A = 'X'.
    LV_MODE = 'A'.
  ELSE.
    LV_MODE = '?'.
  ENDIF.

  IF RB_UPD_A = 'X'.
    LV_UPD = 'A'.
  ELSEIF RB_UPD_S = 'X'.
    LV_UPD = 'S'.
  ELSE.
    LV_UPD = '?'.
  ENDIF.

  LV_HOST    = TXTP_SFTP_HOST.
  LV_PORT    = TXTP_SFTP_PORT.
  LV_BSZ     = TXTP_BATCH_SIZE.
  LV_EXEC    = P_BDC_MODE.
  LV_RETRY   = CHKP_RETRY.
  LV_TIMEOUT = TXTP_TIMEOUT.

  CONDENSE LV_HOST.
  CONDENSE LV_PORT.
  CONDENSE LV_BSZ.
  CONDENSE LV_EXEC.
  CONDENSE LV_TIMEOUT.

  CONCATENATE LV_HOST LV_PORT LV_MODE LV_UPD LV_BSZ
              LV_EXEC LV_RETRY LV_TIMEOUT
         INTO CV_SIG SEPARATED BY '|'.
ENDFORM.
*<<< END FORM BUILD_0200_CFG_SIG

*>>> FORM CONFIRM_0200_LEAVE - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM CONFIRM_0200_LEAVE CHANGING CV_GO TYPE C.
  DATA: LV_CUR_SIG TYPE STRING,
        LV_ANSWER  TYPE C LENGTH 1.

  CV_GO = 'X'.
  PERFORM BUILD_0200_CFG_SIG CHANGING LV_CUR_SIG.

  IF GV_0200_SAVED_SIG IS INITIAL OR LV_CUR_SIG = GV_0200_SAVED_SIG.
    RETURN.
  ENDIF.

  CALL FUNCTION 'POPUP_TO_CONFIRM'
    EXPORTING
      TITLEBAR              = 'Unsaved Configuration'
      TEXT_QUESTION         = 'Configuration has unsaved changes. Save before leaving?'
      TEXT_BUTTON_1         = 'Save'
      TEXT_BUTTON_2         = 'Leave without saving'
      DEFAULT_BUTTON        = '1'
      DISPLAY_CANCEL_BUTTON = 'X'
    IMPORTING
      ANSWER                = LV_ANSWER
    EXCEPTIONS
      OTHERS                = 1.

  IF SY-SUBRC <> 0.
    CV_GO = SPACE.
    RETURN.
  ENDIF.

  CASE LV_ANSWER.
    WHEN '1'.
      PERFORM SAVE_SOURCE_CONFIG.
      IF GV_0200_SAVED_OK IS INITIAL.
        CV_GO = SPACE.
      ENDIF.
    WHEN '2'.
      CV_GO = 'X'.
    WHEN OTHERS.
      CV_GO = SPACE.
  ENDCASE.
ENDFORM.
*<<< END FORM CONFIRM_0200_LEAVE

*>>> FORM safe_pop_screen - moved from Z_BDC_MASS_PO_ENTRY_F01_BUP

FORM safe_pop_screen.
  SET SCREEN 0.
  LEAVE SCREEN.
ENDFORM.
*<<< END FORM safe_pop_screen
