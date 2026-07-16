*&---------------------------------------------------------------------*
*& Report ZBDC_INSERT_SCRIPT_DATA_BUP
*& Data sua theo SHDB recording that (TEST_ME21N.txt + TEST_MIGO.txt):
*&  - ME21N: them BSART=NB, BUKRS=ZF25; plant item = NAME1 (KHONG WERKS)
*&  - MIGO : OK_GO load PO -> OK_POST1; item TAKE_IT/LGOBE/ERFMG
*&---------------------------------------------------------------------*
REPORT zbdc_insert_script_data_bup.

DATA: lt_script TYPE TABLE OF zbdc_sct_def_bup,
      ls_script TYPE zbdc_sct_def_bup.

* Xoa du lieu cu de tranh trung khoa
DELETE FROM zbdc_sct_def_bup.

* ====================================================================
* ME21N BDC Script Data (18 rows) - SAPLMEGUI 0014
* ====================================================================
DEFINE add_me21n.
  clear ls_script.
  ls_script-tcode         = 'ME21N'.
  ls_script-step_seq      = &1.
  ls_script-program_name  = &2.
  ls_script-dynpro_no     = &3.
  ls_script-is_new_screen = &4.
  ls_script-field_name    = &5.
  ls_script-value_type    = &6.
  ls_script-static_value  = &7.
  ls_script-source_column = &8.
  ls_script-row_type      = &9.
  append ls_script to lt_script.
END-OF-DEFINITION.

* --- Man 1: loai PO + vendor (MEPO_TOPLINE) --------------------------
add_me21n '0010' 'SAPLMEGUI' '0014' 'X' ''                        'STATIC'  ''        ''            'H'.
add_me21n '0020' ''          ''     ''  'BDC_OKCODE'              'STATIC'  '/00'     ''            'H'.
add_me21n '0030' ''          ''     ''  'MEPO_TOPLINE-BSART'      'STATIC'  'NB'      ''            'H'.
add_me21n '0040' ''          ''     ''  'MEPO_TOPLINE-SUPERFIELD' 'DYNAMIC' ''        'VENDOR'      'H'.

* --- Man 2: Org Data (MEPO1222) --------------------------------------
add_me21n '0050' 'SAPLMEGUI' '0014' 'X' ''                        'STATIC'  ''        ''            'H'.
add_me21n '0060' ''          ''     ''  'BDC_OKCODE'              'STATIC'  '/00'     ''            'H'.
add_me21n '0070' ''          ''     ''  'MEPO1222-EKORG'          'DYNAMIC' ''        'PURCH_ORG'   'H'.
add_me21n '0080' ''          ''     ''  'MEPO1222-EKGRP'          'DYNAMIC' ''        'PURCH_GROUP' 'H'.
add_me21n '0090' ''          ''     ''  'MEPO1222-BUKRS'          'STATIC'  'ZF25'    ''            'H'.

* --- Item block: lap theo dong CSV, &IDX& = 01,02,... ----------------
* Item grid 0014 (MEPO1211): plant nam o NAME1, WERKS KHONG ton tai!
add_me21n '0100' 'SAPLMEGUI' '0014' 'X' ''                        'STATIC'  ''        ''            'I'.
add_me21n '0110' ''          ''     ''  'BDC_OKCODE'              'STATIC'  '/00'     ''            'I'.
add_me21n '0120' ''          ''     ''  'MEPO1211-EMATN(&IDX&)'   'DYNAMIC' ''        'MATERIAL'    'I'.
add_me21n '0130' ''          ''     ''  'MEPO1211-MENGE(&IDX&)'   'DYNAMIC' ''        'QUANTITY'    'I'.
add_me21n '0140' ''          ''     ''  'MEPO1211-NETPR(&IDX&)'   'DYNAMIC' ''        'NET_PRICE'   'I'.
add_me21n '0150' ''          ''     ''  'MEPO1211-NAME1(&IDX&)'   'DYNAMIC' ''        'PLANT'       'I'.

* --- Man cuoi: Save ----------------------------------------------------
add_me21n '0160' 'SAPLMEGUI' '0014' 'X' ''                        'STATIC'  ''        ''            'H'.
add_me21n '0170' ''          ''     ''  'BDC_OKCODE'              'STATIC'  '=MESAVE' ''            'H'.

* ====================================================================
* MIGO BDC Script Data (12 rows) - SAPLMIGO 0001
* Cau truc: PRE = man OK_GO + man OK_POST1 (header truoc),
*           ITEM = field item gan vao man OK_POST1 (&IDX&)
* ====================================================================
DEFINE add_migo.
  clear ls_script.
  ls_script-tcode         = 'MIGO'.
  ls_script-step_seq      = &1.
  ls_script-program_name  = &2.
  ls_script-dynpro_no     = &3.
  ls_script-is_new_screen = &4.
  ls_script-field_name    = &5.
  ls_script-value_type    = &6.
  ls_script-static_value  = &7.
  ls_script-source_column = &8.
  ls_script-row_type      = &9.
  append ls_script to lt_script.
END-OF-DEFINITION.

* --- Man 1: A01/R01/101 + so PO + OK_GO (load item tu PO) ------------
add_migo '0010' 'SAPLMIGO' '0001' 'X' ''                      'STATIC'  ''          ''            'H'.
add_migo '0020' ''         ''     ''  'BDC_OKCODE'            'STATIC'  '=OK_GO'    ''            'H'.
add_migo '0030' ''         ''     ''  'GODYNPRO-ACTION'       'STATIC'  'A01'       ''            'H'.
add_migo '0040' ''         ''     ''  'GODYNPRO-REFDOC'       'STATIC'  'R01'       ''            'H'.
add_migo '0050' ''         ''     ''  'GODEFAULT_TV-BWART'    'STATIC'  '101'       ''            'H'.
add_migo '0060' ''         ''     ''  'GODYNPRO-PO_NUMBER'    'DYNAMIC' ''          'PO_NUMBER'   'H'.

* --- Man 2: OK_POST1 (item fields se gan vao man nay) ----------------
add_migo '0070' 'SAPLMIGO' '0001' 'X' ''                      'STATIC'  ''          ''            'H'.
add_migo '0080' ''         ''     ''  'BDC_OKCODE'            'STATIC'  '=OK_POST1' ''            'H'.
add_migo '0090' ''         ''     ''  'GODEFAULT_TV-BWART'    'STATIC'  '101'       ''            'H'.

* --- Item fields (KHONG mo man moi - gan tiep vao man OK_POST1) ------
add_migo '0100' ''         ''     ''  'GOITEM-TAKE_IT(&IDX&)' 'STATIC'  'X'         ''            'I'.
add_migo '0110' ''         ''     ''  'GOITEM-LGOBE(&IDX&)'   'DYNAMIC' ''          'STOR_LOC'    'I'.
add_migo '0120' ''         ''     ''  'GOITEM-ERFMG(&IDX&)'   'DYNAMIC' ''          'QUANTITY'    'I'.

* ====================================================================
INSERT zbdc_sct_def_bup FROM TABLE lt_script.
IF sy-subrc = 0.
  COMMIT WORK.
  WRITE: / |SUCCESS: Da nap { lines( lt_script ) } dong script (ME21N + MIGO) vao ZBDC_SCT_DEF_BUP!|.
ELSE.
  ROLLBACK WORK.
  WRITE: / 'ERROR: Co loi khi nap du lieu!'.
ENDIF.
