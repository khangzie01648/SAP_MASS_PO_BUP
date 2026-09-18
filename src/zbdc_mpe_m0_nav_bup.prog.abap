
*& Include ZBDC_MPE_M0_NAV_BUP
*& Purpose Navigation and explicit runtime UI policy
*& fail-closed policy boundaries

*& Convert one persisted/external execution-mode value into the one
*& canonical runtime engine value. Pure: no dynpro/global state access.

FORM canon_exec_mode
  USING    iv_raw     TYPE csequence
  CHANGING cv_exec    TYPE char30
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA lv_raw TYPE string.

  CLEAR: cv_exec, cv_ok, cv_message.
  lv_raw = iv_raw.
  TRANSLATE lv_raw TO UPPER CASE.
  CONDENSE lv_raw NO-GAPS.

  CASE lv_raw.
    WHEN gc_mode_call OR 'CALL' OR 'CT' OR 'CALL_TRANSACTION_MODE'.
      cv_exec = gc_mode_call.
      cv_ok   = abap_true.
    WHEN gc_mode_batch OR 'BATCH' OR 'BISM' OR 'SM35'
      OR 'BATCH_INPUT_SESSION'.
      cv_exec = gc_mode_batch.
      cv_ok   = abap_true.
    WHEN OTHERS.
      IF lv_raw IS INITIAL.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '001' INTO cv_message.
      ELSE.
        MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '002' WITH lv_raw INTO cv_message.
      ENDIF.
  ENDCASE.
ENDFORM.

*& Read the execution-engine radio group exactly as displayed.

FORM read_exec_radios
  CHANGING cv_exec    TYPE char30
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA lv_count TYPE i.

  CLEAR: cv_exec, cv_ok, cv_message, lv_count.

  IF rb_exec_ct = 'X'.
    lv_count = lv_count + 1.
    cv_exec = gc_mode_call.
  ENDIF.
  IF rb_exec_bi = 'X'.
    lv_count = lv_count + 1.
    cv_exec = gc_mode_batch.
  ENDIF.

  IF lv_count = 1.
    cv_ok = abap_true.
  ELSEIF lv_count = 0.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '003' INTO cv_message.
  ELSE.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '004' INTO cv_message.
  ENDIF.
ENDFORM.

*& Read one CALL TRANSACTION display-mode radio group exactly.

FORM read_mode_radios
  CHANGING cv_mode    TYPE char1
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA lv_count TYPE i.

  CLEAR: cv_mode, cv_ok, cv_message, lv_count.

  IF rb_mode_n = 'X'.
    lv_count = lv_count + 1.
    cv_mode = 'N'.
  ENDIF.
  IF rb_mode_e = 'X'.
    lv_count = lv_count + 1.
    cv_mode = 'E'.
  ENDIF.
  IF rb_mode_a = 'X'.
    lv_count = lv_count + 1.
    cv_mode = 'A'.
  ENDIF.

  IF lv_count = 1.
    cv_ok = abap_true.
  ELSEIF lv_count = 0.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '005' INTO cv_message.
  ELSE.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '006' INTO cv_message.
  ENDIF.
ENDFORM.

*& Read one CALL TRANSACTION update-mode radio group exactly.

FORM read_upd_radios
  CHANGING cv_update  TYPE char1
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA lv_count TYPE i.

  CLEAR: cv_update, cv_ok, cv_message, lv_count.

  IF rb_upd_s = 'X'.
    lv_count = lv_count + 1.
    cv_update = 'S'.
  ENDIF.
  IF rb_upd_a = 'X'.
    lv_count = lv_count + 1.
    cv_update = 'A'.
  ENDIF.

  IF lv_count = 1.
    cv_ok = abap_true.
  ELSEIF lv_count = 0.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '007' INTO cv_message.
  ELSE.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '008' INTO cv_message.
  ENDIF.
ENDFORM.

*& Read both CTU preferences. These values remain selected while SM35 is
*& active; SM35 ignores them, but switching back restores the prior choice.

FORM read_ctu_radios
  CHANGING cv_mode    TYPE char1
           cv_update  TYPE char1
           cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_mode_ok TYPE abap_bool,
        lv_upd_ok  TYPE abap_bool,
        lv_message TYPE string.

  CLEAR: cv_mode, cv_update, cv_ok, cv_message.

  PERFORM read_mode_radios
    CHANGING cv_mode lv_mode_ok lv_message.
  IF lv_mode_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  CLEAR lv_message.
  PERFORM read_upd_radios
    CHANGING cv_update lv_upd_ok lv_message.
  IF lv_upd_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Apply one validated policy to global/dynpro fields. Validation happens
*& before any mutation, so a bad caller cannot leave a half-painted state.

FORM apply_policy_state
  USING    iv_exec    TYPE char30
           iv_mode    TYPE char1
           iv_update  TYPE char1
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exec      TYPE char30,
        lv_exec_ok   TYPE abap_bool,
        lv_message   TYPE string,
        lv_z600_exec TYPE char30,
        lv_z600_mode TYPE char1,
        lv_z600_upd  TYPE char1.

  CLEAR: cv_ok, cv_message.

  PERFORM canon_exec_mode
    USING    iv_exec
    CHANGING lv_exec lv_exec_ok lv_message.
  IF lv_exec_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  IF iv_mode <> 'N' AND iv_mode <> 'E' AND iv_mode <> 'A'.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '009' WITH iv_mode INTO cv_message.
    RETURN.
  ENDIF.

  IF iv_update <> 'S' AND iv_update <> 'A'.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '010' WITH iv_update INTO cv_message.
    RETURN.
  ENDIF.

  p_bdc_mode = lv_exec.

  CLEAR: rb_exec_ct, rb_exec_bi.
  IF lv_exec = gc_mode_batch.
    rb_exec_bi = 'X'.
  ELSE.
    rb_exec_ct = 'X'.
  ENDIF.

  CLEAR: rb_mode_n, rb_mode_e, rb_mode_a.
  CASE iv_mode.
    WHEN 'N'. rb_mode_n = 'X'.
    WHEN 'E'. rb_mode_e = 'X'.
    WHEN 'A'. rb_mode_a = 'X'.
  ENDCASE.

  CLEAR: rb_upd_s, rb_upd_a.
  IF iv_update = 'A'.
    rb_upd_a = 'X'.
  ELSE.
    rb_upd_s = 'X'.
  ENDIF.

 "keep one canonical CTU policy beyond Screen 0300. Screen 0500
 "has no BDC-mode radios of its own, so execution must not reconstruct the
 "user choice from later PBO/config state. Every validated policy apply
 "(initial config load or user PAI) refreshes this session-local snapshot.
  lv_z600_exec = lv_exec.
  lv_z600_mode = iv_mode.
  lv_z600_upd  = iv_update.
  EXPORT zexec = lv_z600_exec
         zmode = lv_z600_mode
         zupd  = lv_z600_upd
    TO MEMORY ID 'ZBDC_CTU_POLICY'.

  cv_ok = abap_true.
ENDFORM.

*& Capture the current dynpro radio state. Used by PAI/save only.
*& The function code/origin is deliberately irrelevant.

FORM capture_runtime
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exec    TYPE char30,
        lv_mode    TYPE char1,
        lv_update  TYPE char1,
        lv_exec_ok TYPE abap_bool,
        lv_ctu_ok  TYPE abap_bool,
        lv_apply_ok TYPE abap_bool,
        lv_message TYPE string.

  CLEAR: cv_ok, cv_message.

  PERFORM read_exec_radios
    CHANGING lv_exec lv_exec_ok lv_message.
  IF lv_exec_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  CLEAR lv_message.
  PERFORM read_ctu_radios
    CHANGING lv_mode lv_update lv_ctu_ok lv_message.
  IF lv_ctu_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  PERFORM apply_policy_state
    USING    lv_exec lv_mode lv_update
    CHANGING lv_apply_ok lv_message.
  IF lv_apply_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Validate the current canonical policy without changing it.

FORM check_runtime_policy
  CHANGING cv_ok      TYPE abap_bool
           cv_message TYPE string.

  DATA: lv_exec       TYPE char30,
        lv_radio_exec TYPE char30,
        lv_mode       TYPE char1,
        lv_update     TYPE char1,
        lv_exec_ok    TYPE abap_bool,
        lv_radio_ok   TYPE abap_bool,
        lv_ctu_ok     TYPE abap_bool,
        lv_message    TYPE string.

  CLEAR: cv_ok, cv_message.

  PERFORM canon_exec_mode
    USING    p_bdc_mode
    CHANGING lv_exec lv_exec_ok lv_message.
  IF lv_exec_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  CLEAR lv_message.
  PERFORM read_exec_radios
    CHANGING lv_radio_exec lv_radio_ok lv_message.
  IF lv_radio_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  IF lv_radio_exec <> lv_exec.
    MESSAGE ID 'ZBDC' TYPE 'S' NUMBER '011' INTO cv_message.
    RETURN.
  ENDIF.

  CLEAR lv_message.
  PERFORM read_ctu_radios
    CHANGING lv_mode lv_update lv_ctu_ok lv_message.
  IF lv_ctu_ok <> abap_true.
    cv_message = lv_message.
    RETURN.
  ENDIF.

  cv_ok = abap_true.
ENDFORM.

*& Render enablement only. SM35 ignores CTU options but does not erase them.

FORM render_runtime_policy.
  LOOP AT SCREEN.
    IF screen-group1 = 'BDM' OR screen-group1 = 'UPD'.
      IF p_bdc_mode = gc_mode_batch.
        screen-input = 0.
      ELSE.
        screen-input = 1.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.
ENDFORM.

*& Normalize 0500 GUI/ALV function codes at the UI adapter boundary.
*& Business execution code consumes only canonical commands. Legacy
*& aliases remain isolated here and never participate in domain routing.

FORM canon_0500_cmd
  USING    iv_raw TYPE sy-ucomm
  CHANGING cv_cmd TYPE sy-ucomm.

  cv_cmd = iv_raw.
  TRANSLATE cv_cmd TO UPPER CASE.
  CONDENSE cv_cmd NO-GAPS.

  "0500 business actions are emitted by the ALV toolbar and already use the
  "canonical GC_UCOMM_* values. Retired SE41/business aliases are not routed.
  CASE cv_cmd.
    WHEN 'BACK' OR '&F03' OR 'F03' OR 'RW' OR 'FC_BACK'.
      cv_cmd = 'BACK'.

    WHEN 'EXIT' OR '&F15' OR 'F15' OR 'ENDE' OR 'FC_EXIT'.
      cv_cmd = 'EXIT'.

    WHEN 'CANCEL' OR 'CANC' OR '&F12' OR 'F12' OR 'ECAN' OR 'FC_CANCEL'.
      cv_cmd = 'CANCEL'.

    WHEN OTHERS.
      "Canonical/internal ALV commands remain unchanged.
  ENDCASE.
ENDFORM.
